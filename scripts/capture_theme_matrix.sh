#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: capture_theme_matrix.sh --app-path /path/to/Gaurava.app [options]

Options:
  --sim-name NAME          Simulator name, or "auto" (default: auto)
  --sim-udid UDID          Simulator UDID override
  --output-dir DIR         Evidence directory (default: build/evidence/theme-matrix/<timestamp>)
  --seed PATH              Owner seed JSON (default: scratch/seed/gaurava/owner-seed.json)
  --themes "a b"           Space-separated theme ids (default: editorial-ink midnight-focus)
  --appearances "a b"      Space-separated appearances (default: light dark)
  --settle SECONDS         Seconds to wait after tab switches (default: 2)
USAGE
}

APP_PATH=""
SIM_NAME="auto"
SIM_UDID=""
OUTPUT_DIR="build/evidence/theme-matrix/$(date +%Y%m%d-%H%M%S)"
SEED_PATH="scratch/seed/gaurava/owner-seed.json"
THEMES="editorial-ink midnight-focus"
APPEARANCES="light dark"
SETTLE_SECONDS="2"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --sim-name)
      SIM_NAME="$2"
      shift 2
      ;;
    --sim-udid)
      SIM_UDID="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --seed)
      SEED_PATH="$2"
      shift 2
      ;;
    --themes)
      THEMES="$2"
      shift 2
      ;;
    --appearances)
      APPEARANCES="$2"
      shift 2
      ;;
    --settle)
      SETTLE_SECONDS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Missing or invalid --app-path: $APP_PATH" >&2
  usage
  exit 1
fi

if [[ ! -f "$SEED_PATH" ]]; then
  echo "Missing seed JSON: $SEED_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
resolve_args=(--sim-name "$SIM_NAME")
if [[ -n "$SIM_UDID" ]]; then
  resolve_args+=(--sim-udid "$SIM_UDID")
fi
DESTINATION="$("$SCRIPT_DIR/resolve_sim_destination.sh" "${resolve_args[@]}")"
if [[ -z "$DESTINATION" ]]; then
  echo "No available iOS Simulator found." >&2
  exit 1
fi
SIM_UDID="${DESTINATION##*id=}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print:CFBundleIdentifier" "$APP_PATH/Info.plist")
SEED_B64="$(base64 < "$SEED_PATH" | tr -d '\n')"

mkdir -p "$OUTPUT_DIR"
open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_UDID" -b
xcrun simctl install "$SIM_UDID" "$APP_PATH"

tabs=(summary jabs results log care)

for theme in $THEMES; do
  for appearance in $APPEARANCES; do
    xcrun simctl ui "$SIM_UDID" appearance "$appearance"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    SIMCTL_CHILD_GAURAVA_OWNER_SEED_JSON_B64="$SEED_B64" xcrun simctl launch \
      "$SIM_UDID" \
      "$BUNDLE_ID" \
      --gaurava-reset-local-data-for-testing \
      --gaurava-owner-seed-import "$SEED_PATH" \
      --gaurava-theme-id "$theme" \
      --gaurava-appearance "$appearance" >/dev/null
    sleep 5

    for tab in "${tabs[@]}"; do
      if [[ "$tab" != "summary" ]]; then
        # Launch-argument routing exercises the same parser without triggering
        # the one-time "Open in Gaurava?" confirmation shown by custom-scheme
        # `simctl openurl` on a newly created simulator.
        xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
        xcrun simctl launch \
          "$SIM_UDID" \
          "$BUNDLE_ID" \
          --gaurava-theme-id "$theme" \
          --gaurava-appearance "$appearance" \
          --gaurava-open-url "gaurava://$tab" >/dev/null
        sleep "$SETTLE_SECONDS"
      fi
      xcrun simctl io "$SIM_UDID" screenshot "$OUTPUT_DIR/${theme}-${appearance}-${tab}.png" >/dev/null
    done
  done
done

printf "Theme matrix screenshots: %s\n" "$OUTPUT_DIR"
