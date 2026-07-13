#!/bin/bash
# Stop hook: block while the newest session journal contains secret-like text.

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
SESSIONS_DIR="$PROJECT_DIR/sessions"
LATEST=""

for f in "$SESSIONS_DIR"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-*.md; do
  [ -e "$f" ] || continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then LATEST="$f"; fi
done

[ -z "$LATEST" ] && exit 0

LEAK_LINES=$(grep -nE 'eyJ[A-Za-z0-9_-]{20,}|Bearer +[A-Za-z0-9._-]{20,}|(client_secret|api[_-]?key|password) *[=:] *[^ *<]{8,}|[0-9a-fA-F]{48,}' "$LATEST" 2>/dev/null | cut -d: -f1 | head -n 3 | paste -sd, - || true)
if [ -n "$LEAK_LINES" ]; then
  echo "SESSION-JOURNAL-SECRETS-GUARD: $LATEST contains secret-looking content on line(s) $LEAK_LINES. Redact it to key names or lengths before finishing; matched values are intentionally withheld." >&2
  exit 2
fi

exit 0
