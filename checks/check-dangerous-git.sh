#!/bin/bash
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

CMD="$HOOK_COMMAND"

if echo "$CMD" | grep -qiE 'git[[:space:]]+push\b'; then
  echo '{"decision":"block","reason":"[guardrail] git push is blocked. Push must be done manually by the developer."}'
  exit 2
fi

if echo "$CMD" | grep -qiE 'git[[:space:]]+reset[[:space:]]+--hard'; then
  echo '{"decision":"block","reason":"[guardrail] git reset --hard is blocked — this discards uncommitted work. Run manually if intentional."}'
  exit 2
fi

if echo "$CMD" | grep -qiE 'git[[:space:]]+branch[[:space:]]+-D\b'; then
  echo '{"decision":"block","reason":"[guardrail] git branch -D is blocked. Delete branches manually if intentional."}'
  exit 2
fi

if echo "$CMD" | grep -qiE 'git[[:space:]]+clean[[:space:]].*-[a-zA-Z]*f'; then
  echo '{"decision":"block","reason":"[guardrail] git clean -f is blocked — this deletes untracked files. Run manually if intentional."}'
  exit 2
fi

if echo "$CMD" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+--[[:space:]]+\.'; then
  echo '{"decision":"block","reason":"[guardrail] git checkout -- . is blocked — this discards all working tree changes. Run manually if intentional."}'
  exit 2
fi

exit 0
