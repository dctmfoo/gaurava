#!/bin/bash
# Stop hook: remind about uncommitted straggler files at session end.
#
# NUDGE-ONLY by design — this hook never commits anything. gaurava's
# CLAUDE.md "Git Discipline" requires small, focused, atomic commits grouped
# by workstream, so the agent (not a hook) decides where each file belongs.
# This just surfaces what was left dirty so nothing silently leaks past a
# session.
#
# Skipped entirely (never listed):
#   - files with STAGED changes (agent intends to commit them itself)
#   - submodule gitlinks
#   - OS / editor cruft (.DS_Store, *.tmp, *.bak, *.swp, ~$*)
#   - anything matched by .gitignore (defensive)
#   - files modified within the last FRESH_SEC seconds (still in flight)
#
# Loop prevention: one nudge per Stop cycle via the marker at
# .claude/state/commit-stragglers-pending, same pattern as the other Stop
# hooks.

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR"

STATE_DIR="$PROJECT_DIR/.claude/state"
MARKER="$STATE_DIR/commit-stragglers-pending"
FRESH_SEC="${COMMIT_STRAGGLERS_FRESH_SEC:-300}"   # don't nag about files edited in last 5 min

mkdir -p "$STATE_DIR"

PORCELAIN=$(git status --porcelain=v1 2>/dev/null || true)
if [ -z "$PORCELAIN" ]; then
  [ -f "$MARKER" ] && rm -f "$MARKER"
  exit 0
fi

# Submodule paths (gitlinks, mode 160000).
SUBMODULE_PATHS=$(git ls-files --stage 2>/dev/null | awk -F'\t' '$1 ~ /^160000 /{print $2}')

now=$(date +%s)
NUDGES=()

while IFS= read -r line; do
  [ -z "$line" ] && continue

  index_status="${line:0:1}"
  path="${line:3}"
  case "$path" in *" -> "*) path="${path##* -> }" ;; esac
  path="${path%\"}"
  path="${path#\"}"

  # Skip files with staged changes (agent intends to commit them itself).
  if [ "$index_status" != " " ] && [ "$index_status" != "?" ]; then
    continue
  fi

  # Skip submodule gitlinks.
  if [ -n "$SUBMODULE_PATHS" ] && printf '%s\n' "$SUBMODULE_PATHS" | grep -qxF "$path"; then
    continue
  fi

  # Skip OS / editor cruft.
  case "$path" in
    *.tmp|*.bak|*.bkp|*.swp|*.swo|.DS_Store|*/.DS_Store|'~$'*|*/'~$'*) continue ;;
  esac

  # Defensive: skip anything git would ignore.
  if git check-ignore -q "$path" 2>/dev/null; then
    continue
  fi

  # Freshness gate: skip files modified within the last FRESH_SEC seconds.
  mtime=$(stat -f %m "$path" 2>/dev/null || echo "$now")
  age=$((now - mtime))
  if [ "$age" -lt "$FRESH_SEC" ]; then
    continue
  fi

  NUDGES+=("$path")
done <<< "$PORCELAIN"

if [ ${#NUDGES[@]} -eq 0 ]; then
  [ -f "$MARKER" ] && rm -f "$MARKER"
  exit 0
fi

# Stragglers exist. If already nudged this cycle, end with a one-line warning
# instead of blocking again.
if [ -f "$MARKER" ]; then
  rm -f "$MARKER"
  {
    echo "warning: ${#NUDGES[@]} straggler file(s) still uncommitted after nudge; session ending anyway:"
    for f in "${NUDGES[@]}"; do echo "  - $f"; done
  } >&2
  exit 0
fi

touch "$MARKER"
{
  echo "STRAGGLER-REMINDER: ${#NUDGES[@]} dirty file(s) need a focused commit (or .gitignore entry / archive / move). Per CLAUDE.md "'"'"Git Discipline"'"'", group by workstream — do not lump unrelated work, and remember the TestFlight-before-handoff rule for native changes:"
  for f in "${NUDGES[@]}"; do echo "  - $f"; done
} >&2
exit 2
