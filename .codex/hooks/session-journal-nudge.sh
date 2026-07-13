#!/bin/bash
# Stop hook: nudge the agent to create/update the session journal.
#
# Algorithm (capped at 1 nudge per Stop cycle to prevent infinite loops):
#   1. Find the newest journal (sessions/YYYY-MM-DD-HHMM-<slug>.md).
#   2. None exists AND no marker  -> create marker, "create a journal" reminder
#      (stderr + exit 2; Stop blocks once so the agent sees it and acts).
#   3. None exists AND marker     -> agent ignored the nudge; warn, clear
#      marker, exit 0 (session ends without a journal).
#   4. Journal mtime < 120s        -> agent updated it this turn; clear marker;
#      exit 0.
#   5. Journal stale AND no marker -> create marker, "update the journal"
#      reminder (THIN vs DETAILED) via stderr + exit 2.
#   6. Journal stale AND marker    -> agent ignored the nudge; warn, clear
#      marker, exit 0.
#
# The marker at .claude/state/journal-nudge-pending caps us to ONE nudge per
# Stop cycle. Claude Code has no built-in Stop-hook loop prevention, so this
# touchstone is mandatory.

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SESSIONS_DIR="$PROJECT_DIR/sessions"
STATE_DIR="$PROJECT_DIR/.claude/state"
MARKER="$STATE_DIR/journal-nudge-pending"

mkdir -p "$SESSIONS_DIR" "$STATE_DIR"

# Find newest journal (strict YYYY-MM-DD-HHMM-<slug>.md pattern, so build
# reports and handoffs in sessions/ are not mistaken for the journal).
LATEST=""
for f in "$SESSIONS_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
    LATEST="$f"
  fi
done

# Case 1: No journal exists.
if [ -z "$LATEST" ]; then
  if [ -f "$MARKER" ]; then
    rm -f "$MARKER"
    echo "warning: session journal was not created after nudge; session ending without one." >&2
    exit 0
  fi
  touch "$MARKER"
  echo "SESSION-JOURNAL-REMINDER: No session journal exists at $SESSIONS_DIR. Per CLAUDE.md "'"'"Session Journal Discipline"'"'", create one (filename YYYY-MM-DD-HHMM-<slug>.md, timestamp in IST) before finishing this turn, using the template in CLAUDE.md." >&2
  exit 2
fi

# Case 2: Journal exists — check freshness (Mac stat -f, Linux stat -c).
if stat -f %m "$LATEST" >/dev/null 2>&1; then
  MTIME=$(stat -f %m "$LATEST")
else
  MTIME=$(stat -c %Y "$LATEST")
fi
NOW=$(date +%s)
AGE=$(( NOW - MTIME ))

if [ "$AGE" -lt 120 ]; then
  # Fresh — agent updated this turn.
  [ -f "$MARKER" ] && rm -f "$MARKER"
  exit 0
fi

# Journal stale (>120s old).
if [ -f "$MARKER" ]; then
  rm -f "$MARKER"
  echo "warning: session journal $LATEST still stale after nudge (${AGE}s); session ending anyway." >&2
  exit 0
fi

touch "$MARKER"

# Detect journal mode: first non-empty line under "## Live plan pointer".
# THIN = pointer set to a real path; DETAILED = empty or "none".
PLAN_LINE=$(awk '
  /^## Live plan pointer[[:space:]]*$/ { flag = 1; next }
  flag && /^## / { exit }
  flag && NF { print; exit }
' "$LATEST" 2>/dev/null || true)

PLAN_LINE_TRIMMED=$(printf '%s' "$PLAN_LINE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
PLAN_LINE_LC=$(printf '%s' "$PLAN_LINE_TRIMMED" | tr '[:upper:]' '[:lower:]')

if [ -z "$PLAN_LINE_TRIMMED" ] || [ "$PLAN_LINE_LC" = "none" ] || [ "$PLAN_LINE_LC" = "<none>" ]; then
  # DETAILED mode — no governing doc; journal is the canonical record.
  echo "SESSION-JOURNAL-REMINDER (DETAILED mode — Live plan pointer is 'none'): $LATEST was last touched ${AGE}s ago. Per CLAUDE.md "'"'"Session Journal Discipline"'"'", update Milestones / Commits / Files-touched / Where-we-are / Next-step + the 'Last updated' timestamp before finishing this turn. If a plan/spec/handoff/tracker is in fact governing this session, set 'Live plan pointer' to that path and switch to THIN mode." >&2
else
  # THIN mode — governing doc exists; journal is a thin index.
  echo "SESSION-JOURNAL-REMINDER (THIN mode — Live plan pointer: ${PLAN_LINE_TRIMMED}): $LATEST was last touched ${AGE}s ago. Per CLAUDE.md journal-mode discipline, append a ONE-LINE milestone referencing the governing doc (section / decision / phase / commit hash). Do NOT re-narrate its content. Update 'Last updated' + 'Where we are now' + 'Next step for a fresh agent' as needed; let the governing doc carry the rest." >&2
fi
exit 2
