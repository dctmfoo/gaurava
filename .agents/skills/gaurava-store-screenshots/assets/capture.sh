#!/usr/bin/env bash
# Capture MarketingScreenshotTests from the REAL seeded app, per locale, into the
# skill's captures dirs — the input the build_minihue*.py generators consume.
#
# Usage:
#   capture.sh <iphone|ipad> [light|dark] [tirzepatide|semaglutide] [locale ...]
# Defaults: theme=light, med=tirzepatide, locales="en hi ta te".
#
# Destinations (matches what build_minihue*.py / the marketing site read):
#   iphone  light  -> assets/captures/<locale>/
#   iphone  dark   -> assets/captures-dark/<locale>/
#   ipad    light  -> assets/captures-ipad/<locale>/
#   ipad    dark   -> assets/captures-ipad-dark/<locale>/
#   + semaglutide  -> <dir>-sema/<locale>/   (e.g. captures-sema; feeds the
#                     gaurava.app semaglutide Care shot — keeps the default
#                     tirzepatide deck captures untouched)
#
# Locale is driven by xcodebuild -testLanguage/-testRegion (host env vars do NOT
# cross into the sim test runner). Theme (dark) and medication (semaglutide) are
# forced via SWIFT_ACTIVE_COMPILATION_CONDITIONS — MarketingSeedTheme.requested()
# / MarketingSeedVariant.requested() fall back to the GAURAVA_MARKETING_DARK /
# GAURAVA_MARKETING_SEMAGLUTIDE flags, since runner env/args can't be injected
# from the CLI either.
set -euo pipefail

DEVICE="${1:?usage: capture.sh <iphone|ipad> [light|dark] [tirzepatide|semaglutide] [locale ...]}"
THEME="light"; MED="tirzepatide"; shift || true
if [ "${1:-}" = "light" ] || [ "${1:-}" = "dark" ]; then THEME="$1"; shift; fi
if [ "${1:-}" = "tirzepatide" ] || [ "${1:-}" = "semaglutide" ]; then MED="$1"; shift; fi
LOCALES=("$@"); [ ${#LOCALES[@]} -eq 0 ] && LOCALES=(en hi ta te)

ASSETS="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$ASSETS/../../../.." && pwd -P)"
cd "$REPO"

# Self-heal the scheme's attachment lifetime. Xcode 26 strips XCTAttachment
# screenshots on test success unless the TestAction forces keepAlways; XcodeGen
# can't express userAttachmentLifetime, so an `xcodegen generate` (e.g. via
# `make bump-build`) would wipe it and silently re-break capture ("wrote 0
# screens"). Re-apply it here, idempotently, before every run.
SCHEME_FILE="Gaurava.xcodeproj/xcshareddata/xcschemes/Gaurava.xcscheme"
if [ -f "$SCHEME_FILE" ]; then
  python3 - "$SCHEME_FILE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if "userAttachmentLifetime" not in s:
    s = s.replace(
        'shouldUseLaunchSchemeArgsEnv = "YES"',
        'shouldUseLaunchSchemeArgsEnv = "YES"\n'
        '      systemAttachmentLifetime = "keepNever"\n'
        '      userAttachmentLifetime = "keepAlways"', 1)
    open(p, "w").write(s)
    print("  [capture.sh] re-applied scheme attachment lifetime (keepAlways)")
PY
fi

# Route each variant to its OWN captures dir so a dark / semaglutide run never
# clobbers the default light-tirzepatide deck captures.
case "$DEVICE" in
  iphone) SIM="iPhone 17 Pro Max"; CAPROOT="$ASSETS/captures";
          [ "$THEME" = dark ] && CAPROOT="$ASSETS/captures-dark";;
  ipad)   SIM="iPad Pro 13-inch (M5)"; CAPROOT="$ASSETS/captures-ipad";
          [ "$THEME" = dark ] && CAPROOT="$ASSETS/captures-ipad-dark";;
  *) echo "bad device '$DEVICE' (iphone|ipad)"; exit 1;;
esac
[ "$MED" = semaglutide ] && CAPROOT="${CAPROOT}-sema"

UDID="$(xcrun simctl list devices available | grep "$SIM" | head -1 | grep -oE '[0-9A-F-]{36}')"
[ -z "$UDID" ] && { echo "No available sim matching '$SIM'"; exit 1; }
echo ">> $DEVICE/$THEME/$MED  sim=$SIM  udid=$UDID  locales=${LOCALES[*]}  -> $CAPROOT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi || true

STAMP="$(date +%Y%m%d-%H%M%S)"
OUTROOT="build/asset-refresh/${DEVICE}-${THEME}-${STAMP}"
DERIVED="build/DerivedData/MARKETING-${DEVICE}-${THEME}-${MED}"
mkdir -p "$OUTROOT"

CONDS=""
[ "$THEME" = dark ]       && CONDS="$CONDS GAURAVA_MARKETING_DARK"
[ "$MED" = semaglutide ]  && CONDS="$CONDS GAURAVA_MARKETING_SEMAGLUTIDE"
DARKFLAG=()
[ -n "$CONDS" ] && DARKFLAG=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited)$CONDS")

region_for() { case "$1" in en) echo US;; *) echo IN;; esac; }

for L in "${LOCALES[@]}"; do
  R="$(region_for "$L")"
  RESULT="$OUTROOT/marketing-$L.xcresult"
  echo "==== capture $DEVICE/$THEME  $L/$R ===="
  xcodebuild test -project Gaurava.xcodeproj -scheme Gaurava -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    -only-testing:GauravaUITests/MarketingScreenshotTests \
    -resultBundlePath "$RESULT" -parallel-testing-enabled NO \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
    SWIFT_STRICT_CONCURRENCY=complete ${DARKFLAG[@]+"${DARKFLAG[@]}"} \
    -testLanguage "$L" -testRegion "$R" test

  EXDIR="$OUTROOT/extracted-$L"
  rm -rf "$EXDIR"; mkdir -p "$EXDIR"
  ok=""
  for attempt in 1 2 3 4; do
    if xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXDIR" 2>/dev/null; then ok=1; break; fi
    echo "  (attachments not ready, retry $attempt) "; sleep 6
  done
  [ -z "$ok" ] && { echo "  !! could not export attachments for $L"; continue; }

  DEST="$CAPROOT/$L"; mkdir -p "$DEST"
  python3 - "$EXDIR" "$DEST" <<'PY'
import json, os, re, sys, shutil
exdir, dest = sys.argv[1], sys.argv[2]
man = json.load(open(os.path.join(exdir, "manifest.json")))
# Keep ONLY our explicitly-named screenshots ("01-summary-journey", "06-card-story",
# …). With systemAttachmentLifetime=keepNever the auto UI-snapshot / screen-recording
# junk shouldn't appear, but filter defensively on the NN- prefix regardless.
NAMED = re.compile(r"^\d\d[a-z]?-")
n = 0
for test in man:
    for a in test.get("attachments", []):
        hr = a["suggestedHumanReadableName"]
        if not NAMED.match(hr):
            continue
        base = hr.split("_0_")[0]
        if not base.endswith(".png"):
            base += ".png"
        src = os.path.join(exdir, a["exportedFileName"])
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(dest, base)); n += 1
print(f"  wrote {n} screens -> {dest}")
PY
done

xcrun simctl status_bar "$UDID" clear || true
echo ">> DONE $DEVICE/$THEME ${LOCALES[*]}"
