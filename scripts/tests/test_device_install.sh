#!/usr/bin/env bash
# Regression test for issue #17. The real script must ask CoreDevice for only
# available paired physical devices before applying DEVICE_INSTALL_ONLY.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/bin"
INSTALL_LOG="$TMP/installed-devices"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/xcodegen" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$FAKE_BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$DEVICE_DERIVED/Build/Products/Debug-iphoneos/Gaurava.app"
exit 0
EOF

cat > "$FAKE_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1 $2 $3" = "devicectl list devices" ]; then
  case "$*" in
    *"Reality = 'physical' AND State = 'available (paired)'"*)
      cat <<'DEVICES'
Name            Hostname   Identifier                             State                Model                                Reality
-------------   --------   ------------------------------------   ------------------   ----------------------------------   --------
Demo iPad                   0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9   available (paired)   iPad (10th generation) (iPad13,18)   physical
iPhone                     1F2E3D4C-5B6A-7089-9182-A3B4C5D6E7F8   available (paired)   iPhone 16 Pro Max (iPhone17,2)       physical
DEVICES
      ;;
    *)
      cat <<'DEVICES'
Name                         Hostname   Identifier                             State                Model                                Reality
--------------------------   --------   ------------------------------------   ------------------   ----------------------------------   ---------
Connected iPhone simulator              16BF2156-F4BF-4E63-8BC7-D0CDDF6CA24A   connected            iPhone 17 Pro (iPhone18,1)           simulated
Demo iPad                                0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9   available (paired)   iPad (10th generation) (iPad13,18)   physical
iPhone                                  1F2E3D4C-5B6A-7089-9182-A3B4C5D6E7F8   available (paired)   iPhone 16 Pro Max (iPhone17,2)       physical
Unavailable iPhone                      11111111-2222-3333-4444-555555555555   unavailable          iPhone 15 Pro (iPhone16,1)           physical
DEVICES
      ;;
  esac
  exit 0
fi

if [ "$1 $2 $3 $4" = "devicectl device install app" ]; then
  printf '%s\n' "$6" >> "$INSTALL_LOG"
  exit 0
fi

if [ "$1 $2 $3 $4" = "devicectl device process launch" ]; then
  exit 0
fi

printf 'Unexpected xcrun invocation: %s\n' "$*" >&2
exit 2
EOF

chmod +x "$FAKE_BIN/xcodegen" "$FAKE_BIN/xcodebuild" "$FAKE_BIN/xcrun"

export PATH="$FAKE_BIN:$PATH"
export DEVICE_DERIVED="$TMP/derived"
export DEVICE_INSTALL_ONLY="iPhone"
export INSTALL_LOG

"$REPO_ROOT/scripts/device_install.sh" >/dev/null

EXPECTED="1F2E3D4C-5B6A-7089-9182-A3B4C5D6E7F8"
ACTUAL="$(cat "$INSTALL_LOG")"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  printf 'FAIL: expected only paired physical iPhone %s, installed on:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  exit 1
fi

printf 'PASS: iPhone-only install selected one available paired physical iPhone.\n'
