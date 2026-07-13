#!/usr/bin/env bash
# Development build + install on ALL connected iOS devices (iPhone + iPad).
#
# This is the local dogfooding step that REPLACES TestFlight for these builds
# (solo, unreleased app). It builds one Debug, development-signed device build
# and installs + launches it on every attached iPhone/iPad, preserving the data
# already on each device unless DEVICE_UNINSTALL_FIRST=1 is set for an explicit
# sandbox/reset lane.
#
# Signing: uses automatic signing via `-allowProvisioningUpdates`. This requires
# the machine to be able to manage provisioning — i.e. signed into Xcode with
# the developer Apple ID (Xcode > Settings > Accounts), or an App Store Connect
# API key WITH "Access to Developer Resources" exported via the env vars below.
# The first device build also has to bind the App Group `group.com.nags.gaurava`
# to the app + widget App IDs; automatic signing does this once. Each NEW device
# (e.g. the iPad) must be registered in the team's development profile once via
# Xcode automatic signing before it can install; an unregistered device is
# reported as a per-device warning rather than failing the whole run.
#
# Optional env overrides:
#   APP_SCHEME (Gaurava), APP_BUNDLE_ID (com.nags.gaurava), CONFIGURATION (Debug),
#   APPLE_TEAM_ID (your Apple Developer Team ID), DEVICE_DERIVED (build/device-derived),
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH (to use an API key for signing),
#   DEVICE_INSTALL_ONLY (substring filter, e.g. "iPad", to limit to some devices),
#   DEVICE_UNINSTALL_FIRST (1 to uninstall APP_BUNDLE_ID before install).
set -euo pipefail

SCHEME="${APP_SCHEME:-Gaurava}"
BUNDLE_ID="${APP_BUNDLE_ID:-com.nags.gaurava}"
CONFIG="${CONFIGURATION:-Debug}"
TEAM="${APPLE_TEAM_ID:-}"
DERIVED="${DEVICE_DERIVED:-build/device-derived}"
FILTER="${DEVICE_INSTALL_ONLY:-}"
UNINSTALL_FIRST="${DEVICE_UNINSTALL_FIRST:-0}"

echo "==> Regenerating Xcode project"
command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null

echo "==> Locating available paired physical devices"
# CoreDevice also lists every simulator it knows about. Filter by the explicit
# Reality and State columns before applying the owner-facing name/model filter,
# so DEVICE_INSTALL_ONLY=iPhone can never match an iPhone simulator.
DEVICE_LINES="$(xcrun devicectl list devices \
  --filter "Reality = 'physical' AND State = 'available (paired)'" \
  2>/dev/null | grep -iE 'iphone|ipad' || true)"
if [ -n "$FILTER" ]; then
  DEVICE_LINES="$(printf '%s\n' "$DEVICE_LINES" | grep -i "$FILTER" || true)"
fi
# CoreDevice identifiers (UUID form) — one per device line; the hostname column
# carries a name, not a UUID, so this matches only the Identifier column.
COREIDS="$(printf '%s\n' "$DEVICE_LINES" \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | sort -u || true)"

if [ -z "$COREIDS" ]; then
  echo "ERROR: no available paired physical iOS device found. Connect/unlock the device(s) and trust this Mac." >&2
  exit 1
fi
echo "    devices:"
printf '%s\n' "$DEVICE_LINES" | sed 's/^/      /'

AUTH_FLAGS=()
if [ -n "${ASC_KEY_PATH:-}" ] && [ -f "${ASC_KEY_PATH}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  echo "==> Using App Store Connect API key for signing ($ASC_KEY_ID)"
  AUTH_FLAGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

echo "==> Building $SCHEME ($CONFIG) for iOS device"
set +e
xcodebuild \
  -project Gaurava.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  "${AUTH_FLAGS[@]+"${AUTH_FLAGS[@]}"}" \
  DEVELOPMENT_TEAM="$TEAM" \
  build
BUILD_RC=$?
set -e
if [ $BUILD_RC -ne 0 ]; then
  echo "" >&2
  echo "ERROR: device build failed (likely code signing)." >&2
  echo "One-time fix: open Gaurava.xcodeproj in Xcode, select the Gaurava and" >&2
  echo "GauravaWidgets targets, enable Automatic signing for team $TEAM, and let" >&2
  echo "Xcode create/bind the App Group 'group.com.nags.gaurava' and the dev" >&2
  echo "profiles. Build/run once to EACH device (iPhone and iPad) so both are" >&2
  echo "registered. After that this target works headless." >&2
  exit $BUILD_RC
fi

APP="$DERIVED/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
if [ ! -d "$APP" ]; then
  echo "ERROR: built app not found at $APP" >&2
  exit 1
fi

INSTALLED=0
FAILED=0
while IFS= read -r COREID; do
  [ -n "$COREID" ] || continue
  if [ "$UNINSTALL_FIRST" = "1" ]; then
    echo "==> Removing existing $BUNDLE_ID on $COREID for a fresh install"
    set +e
    xcrun devicectl device uninstall app --device "$COREID" "$BUNDLE_ID"
    UNINSTALL_RC=$?
    set -e
    if [ $UNINSTALL_RC -ne 0 ]; then
      echo "    No existing $BUNDLE_ID removal confirmed (exit $UNINSTALL_RC); continuing with install."
    fi
  fi
  echo "==> Installing on $COREID"
  set +e
  xcrun devicectl device install app --device "$COREID" "$APP"
  INSTALL_RC=$?
  set -e
  if [ $INSTALL_RC -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "WARNING: could not install on $COREID. Common one-time fixes:" >&2
    echo "  - Enable Developer Mode: Settings > Privacy & Security > Developer" >&2
    echo "    Mode > On, then restart the device (required; error 10005)." >&2
    echo "  - Unlock/trust the device so the Developer Disk Image can mount." >&2
    echo "  - Register it in the dev profile (build to it once from Xcode)." >&2
    continue
  fi
  echo "==> Launching $BUNDLE_ID on $COREID"
  xcrun devicectl device process launch --device "$COREID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  INSTALLED=$((INSTALLED + 1))
done <<< "$COREIDS"

if [ "$INSTALLED" -eq 0 ]; then
  echo "ERROR: could not install on any attached device ($FAILED failed)." >&2
  exit 1
fi

if [ "$UNINSTALL_FIRST" = "1" ]; then
  echo "==> Done. Fresh-installed on $INSTALLED device(s); $FAILED skipped. App data reset for $BUNDLE_ID."
else
  echo "==> Done. Installed on $INSTALLED device(s); $FAILED skipped. Data preserved."
fi
