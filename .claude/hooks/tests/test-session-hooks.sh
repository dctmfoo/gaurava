#!/bin/bash
# Smoke test for the session-journal hooks. Runs each hook against a throwaway
# CLAUDE_PROJECT_DIR so the real repo is never touched.
#
# Usage: .claude/hooks/tests/test-session-hooks.sh
# Exit 0 = all pass; non-zero = a check failed.

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POINTER="$HOOKS_DIR/session-journal-pointer.sh"
NUDGE="$HOOKS_DIR/session-journal-nudge.sh"
STRAGGLERS="$HOOKS_DIR/commit-stragglers-nudge.sh"
APPLE_DOCS="$HOOKS_DIR/apple-docs-reminder.sh"
SECRETS="$HOOKS_DIR/journal-secrets-guard.sh"

pass=0
fail=0
ok()   { echo "  PASS: $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail+1)); }

mk_project() {
  local d
  d=$(mktemp -d)
  mkdir -p "$d/sessions" "$d/.claude/state"
  echo "$d"
}

OLD_TS="202601010000"   # touch -t stamp, comfortably > 120s old

echo "== session-journal-pointer.sh =="
P=$(mk_project)
OUT=$(CLAUDE_PROJECT_DIR="$P" "$POINTER")
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName']=='SessionStart'; assert 'No prior session journal' in d['hookSpecificOutput']['additionalContext']" 2>/dev/null; then
  ok "no journal -> valid JSON, 'No prior session journal'"
else
  bad "no journal -> expected valid JSON mentioning no journal; got: $OUT"
fi

printf '# Session: demo\n\n## Live plan pointer\nnone\n' > "$P/sessions/2026-06-04-1410-demo.md"
OUT=$(CLAUDE_PROJECT_DIR="$P" "$POINTER")
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '2026-06-04-1410-demo.md' in d['hookSpecificOutput']['additionalContext']" 2>/dev/null; then
  ok "journal present -> pointer names the journal"
else
  bad "journal present -> expected pointer to name journal; got: $OUT"
fi

printf '# Build report\n' > "$P/sessions/build-9-report.md"
printf '# Handoff\n' > "$P/sessions/handoff-foo.md"
OUT=$(CLAUDE_PROJECT_DIR="$P" "$POINTER")
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); a=d['hookSpecificOutput']['additionalContext']; assert '2026-06-04-1410-demo.md' in a and 'build-9-report' not in a and 'handoff-foo' not in a" 2>/dev/null; then
  ok "reports/handoffs ignored -> only the journal pattern is matched"
else
  bad "reports/handoffs should be ignored; got: $OUT"
fi
rm -rf "$P"

echo "== apple-docs-reminder.sh =="
P=$(mk_project)
OUT=$(printf '%s' '{"prompt":"hello"}' | CLAUDE_PROJECT_DIR="$P" "$APPLE_DOCS")
[ -z "$OUT" ] && ok "plain prompt without Swift repo -> silent" || bad "plain prompt should be silent; got: $OUT"
mkdir -p "$P/App"; printf 'import SwiftUI\n' > "$P/App/Demo.swift"
OUT=$(printf '%s' '{"prompt":"update the documentation wording"}' | CLAUDE_PROJECT_DIR="$P" "$APPLE_DOCS")
[ -z "$OUT" ] && ok "plain prompt in Swift repo -> silent" || bad "plain prompt in Swift repo should be silent; got: $OUT"
OUT=$(printf '%s' '{"prompt":"change the SwiftUI screen"}' | CLAUDE_PROJECT_DIR="$P" "$APPLE_DOCS")
if echo "$OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName']=='UserPromptSubmit'; assert 'apple-platform-think' in d['hookSpecificOutput']['additionalContext']" 2>/dev/null; then
  ok "Swift repo -> valid Apple grounding context"
else
  bad "Swift repo -> expected grounding JSON; got: $OUT"
fi
rm -rf "$P"

echo "== journal-secrets-guard.sh =="
P=$(mk_project)
J="$P/sessions/2026-06-04-1410-secrets.md"
printf '# Session: safe\n\nNo credentials here.\n' > "$J"
CLAUDE_PROJECT_DIR="$P" "$SECRETS" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "safe journal -> exit 0" || bad "safe journal -> expected exit 0 (rc=$rc)"
printf '# Session: leaked\n\nBearer abcdefghijklmnopqrstuvwxyz123456\n' > "$J"
ERR=$(CLAUDE_PROJECT_DIR="$P" "$SECRETS" 2>&1 >/dev/null); rc=$?
{ [ "$rc" -eq 2 ] && echo "$ERR" | grep -q "SECRETS-GUARD" && ! echo "$ERR" | grep -q "abcdefghijklmnopqrstuvwxyz123456"; } \
  && ok "secret-like journal -> exit 2 + guard message" \
  || bad "secret-like journal -> expected redacted exit 2 + guard (rc=$rc): $ERR"
rm -rf "$P"

echo "== session-journal-nudge.sh =="
P=$(mk_project)
CLAUDE_PROJECT_DIR="$P" "$NUDGE" 2>/dev/null; rc=$?
[ "$rc" -eq 2 ] && [ -f "$P/.claude/state/journal-nudge-pending" ] \
  && ok "no journal, 1st run -> exit 2 + marker created" \
  || bad "no journal, 1st run -> expected exit 2 + marker (rc=$rc)"
CLAUDE_PROJECT_DIR="$P" "$NUDGE" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$P/.claude/state/journal-nudge-pending" ] \
  && ok "no journal, 2nd run -> exit 0 + marker cleared (loop guard)" \
  || bad "no journal, 2nd run -> expected exit 0 + marker cleared (rc=$rc)"
rm -rf "$P"

P=$(mk_project)
printf '# Session: fresh\n\n## Live plan pointer\nnone\n' > "$P/sessions/2026-06-04-1410-fresh.md"
CLAUDE_PROJECT_DIR="$P" "$NUDGE" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "fresh journal (<120s) -> exit 0" || bad "fresh journal -> expected exit 0 (rc=$rc)"
rm -rf "$P"

P=$(mk_project)
J="$P/sessions/2026-06-04-1410-detailed.md"
printf '# Session: detailed\n\n## Live plan pointer\nnone\n' > "$J"
touch -t "$OLD_TS" "$J"
ERR=$(CLAUDE_PROJECT_DIR="$P" "$NUDGE" 2>&1 >/dev/null); rc=$?
{ [ "$rc" -eq 2 ] && echo "$ERR" | grep -q "DETAILED mode"; } \
  && ok "stale DETAILED journal -> exit 2 + DETAILED nudge" \
  || bad "stale DETAILED journal -> expected exit 2 + DETAILED (rc=$rc): $ERR"
rm -rf "$P"

P=$(mk_project)
J="$P/sessions/2026-06-04-1410-thin.md"
printf '# Session: thin\n\n## Live plan pointer\ndocs/some-plan.html\n' > "$J"
touch -t "$OLD_TS" "$J"
ERR=$(CLAUDE_PROJECT_DIR="$P" "$NUDGE" 2>&1 >/dev/null); rc=$?
{ [ "$rc" -eq 2 ] && echo "$ERR" | grep -q "THIN mode"; } \
  && ok "stale THIN journal -> exit 2 + THIN nudge" \
  || bad "stale THIN journal -> expected exit 2 + THIN (rc=$rc): $ERR"
rm -rf "$P"

echo "== commit-stragglers-nudge.sh =="
P=$(mk_project)
git -C "$P" init -q
git -C "$P" config user.email t@t.t; git -C "$P" config user.name t
OUT=$(CLAUDE_PROJECT_DIR="$P" "$STRAGGLERS" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "clean repo -> exit 0, silent" || bad "clean repo -> expected exit 0 (rc=$rc): $OUT"

# A stale, unstaged, untracked file should nudge.
echo hi > "$P/leftover.txt"
touch -t "$OLD_TS" "$P/leftover.txt"
ERR=$(CLAUDE_PROJECT_DIR="$P" "$STRAGGLERS" 2>&1 >/dev/null); rc=$?
{ [ "$rc" -eq 2 ] && echo "$ERR" | grep -q "leftover.txt"; } \
  && ok "stale straggler -> exit 2 + lists file" \
  || bad "stale straggler -> expected exit 2 listing file (rc=$rc): $ERR"
# 2nd run -> loop guard ends the turn.
ERR=$(CLAUDE_PROJECT_DIR="$P" "$STRAGGLERS" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && ok "straggler 2nd run -> exit 0 (loop guard)" || bad "straggler 2nd run -> expected exit 0 (rc=$rc): $ERR"
rm -rf "$P"

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
