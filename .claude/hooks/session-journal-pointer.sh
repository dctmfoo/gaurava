#!/bin/bash
# SessionStart hook: inject a pointer to the most recent session journal so a
# new / resumed agent knows where to continue from.
#
# Emits JSON with hookSpecificOutput.additionalContext (context-budget
# conscious — only the path + a short header preview, NOT the full journal).
# The agent reads the pointer on start and opens the file itself.
#
# gaurava is a single repo, so this hook only points to the newest journal
# (there is no multi-repo reverse-index). The session-journal discipline is
# published as a standalone pattern at github.com/dctmfoo/session-journal.
# See CLAUDE.md "Session Journal Discipline".

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SESSIONS_DIR="$PROJECT_DIR/sessions"

mkdir -p "$SESSIONS_DIR"

# Find newest journal. Journals match the strict filename pattern
# YYYY-MM-DD-HHMM-<slug>.md, so build reports (build-N-report.md), handoffs
# (handoff-*.md), and README.md are naturally excluded.
LATEST=""
for f in "$SESSIONS_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
    LATEST="$f"
  fi
done

if [ -z "$LATEST" ]; then
  MSG="No prior session journal found in $SESSIONS_DIR. Per CLAUDE.md "'"'"Session Journal Discipline"'"'", once the user's first message clarifies the session intent, create a new journal (filename YYYY-MM-DD-HHMM-<slug>.md, timestamp in IST) using the template in CLAUDE.md."
else
  REL=$(echo "$LATEST" | sed "s|^$PROJECT_DIR/||")
  # Read just the header (first ~20 lines) for a quick orient.
  HEADER=$(head -n 20 "$LATEST" | awk 'BEGIN{ORS="\\n"} {print}')
  MSG="Most recent session journal: $REL. Read it first to understand where the previous session left off before acting on the user's prompt. If continuing the same work (Status ACTIVE and Last updated within ~2h), append to that file; otherwise create a fresh journal per CLAUDE.md "'"'"Session Journal Discipline"'"'". Header preview:\\n$HEADER"
fi

# JSON-escape the message safely via python (robust for arbitrary content).
if command -v python3 >/dev/null 2>&1; then
  ESCAPED=$(python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "$MSG")
elif command -v python >/dev/null 2>&1; then
  ESCAPED=$(python -c "import sys,json; print(json.dumps(sys.argv[1]))" "$MSG")
else
  ESCAPED=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  ESCAPED="\"$ESCAPED\""
fi

printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' "$ESCAPED"
exit 0
