#!/bin/bash
# UserPromptSubmit hook: re-inject Apple API grounding before agent action.

set -e

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || true)

MATCHES=0
if printf '%s' "$PROMPT" | grep -qiE 'swift|swiftui|swiftdata|cloudkit|xcode|widget|app intent|healthkit|watchconnectivity|activitykit|xctest|ios|ipados|macos|watchos|apple|api|simulator|entitlement|signing|catalog|spec'; then
  MATCHES=1
fi

if [ "$MATCHES" = "0" ]; then
  exit 0
fi

MSG="Apple-platform grounding (hard rule, CLAUDE.md/PLAN.md): before asserting or locking an Apple API, availability, deprecation, or platform behavior, use apple-platform-think and its docs ladder (local exports -> offline docset -> current web last). Never state Apple API facts from memory. For UI work also apply swiftui-design-principles."
printf '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "%s"}}\n' "$MSG"
