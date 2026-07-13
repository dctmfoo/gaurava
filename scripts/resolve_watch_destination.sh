#!/usr/bin/env bash
set -euo pipefail

# Resolve a watchOS Simulator `-destination` string for xcodebuild, mirroring
# scripts/resolve_sim_destination.sh but for Apple Watch devices. Prefers a
# booted watch, otherwise the newest runtime + largest/best model. Falls back to
# a generic destination if no concrete simulator is available.

SIM_NAME=""
SIM_UDID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim-name) SIM_NAME="$2"; shift 2 ;;
    --sim-udid) SIM_UDID="$2"; shift 2 ;;
    -h|--help) echo "Usage: resolve_watch_destination.sh [--sim-name NAME] [--sim-udid UDID]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$SIM_UDID" ]]; then
  echo "platform=watchOS Simulator,id=$SIM_UDID"
  exit 0
fi

SIM_NAME_ENV="$SIM_NAME" SIMCTL_LIST_JSON="${SIMCTL_LIST_JSON:-}" python3 - <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

name = (os.environ.get("SIM_NAME_ENV") or "").strip()
override = (os.environ.get("SIMCTL_LIST_JSON") or "").strip()

def runtime_version(key):
    m = re.search(r"watchOS[- ](\d+)(?:[\.-](\d+))?", key)
    return (int(m.group(1)), int(m.group(2) or 0)) if m else (0, 0)

def model_rank(n):
    # Bigger/newer first: Ultra > Series (by number + mm) > SE.
    lower = n.lower()
    series = 0
    m = re.search(r"series\s+(\d+)", lower)
    if m: series = int(m.group(1))
    mm = 0
    m = re.search(r"\((\d+)mm\)", lower)
    if m: mm = int(m.group(1))
    tier = 3 if "ultra" in lower else (2 if "series" in lower else (1 if "se" in lower else 0))
    return (tier, series, mm)

if override:
    raw = Path(override).read_text(encoding="utf-8") if Path(override).exists() else override
else:
    raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"], text=True)
data = json.loads(raw)

candidates = []
for runtime_key, devices in data.get("devices", {}).items():
    if "watchOS" not in runtime_key and "watch" not in runtime_key.lower():
        continue
    for d in devices:
        if not d.get("isAvailable"):
            continue
        if "Apple Watch" not in d.get("name", ""):
            continue
        candidates.append({
            "name": d.get("name", ""),
            "udid": d.get("udid", ""),
            "state": d.get("state", ""),
            "runtime_version": runtime_version(runtime_key),
        })

if not candidates:
    # Let xcodebuild pick any installed watch simulator.
    print("generic/platform=watchOS Simulator")
    sys.exit(0)

if name and name.lower() != "auto":
    matches = [c for c in candidates if c["name"] == name]
    if matches:
        booted = [c for c in matches if c["state"] == "Booted"]
        chosen = max(booted or matches, key=lambda c: c["runtime_version"])
        print(f"platform=watchOS Simulator,id={chosen['udid']}")
        sys.exit(0)

booted = [c for c in candidates if c["state"] == "Booted"]
pool = booted or candidates
chosen = max(pool, key=lambda c: (c["runtime_version"], model_rank(c["name"])))
print(f"platform=watchOS Simulator,id={chosen['udid']}")
PY
