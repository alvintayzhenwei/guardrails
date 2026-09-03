#!/usr/bin/env bash
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
[ "$HOOK_TOOL_NAME" != "Bash" ] && exit 0

CMD="$HOOK_COMMAND"

if echo "$CMD" | grep -qiE 'brew[[:space:]]+(uninstall|rm|remove)\b'; then
  if echo "$CMD" | grep -qiE '[[:space:]](-f|--force)\b'; then
    echo '{"decision":"block","reason":"[guardrail] brew uninstall --force is blocked — ignores dependency checks. Run manually if intentional."}'
    exit 2
  fi
fi

if echo "$CMD" | grep -qiE 'brew[[:space:]]+cleanup[[:space:]].*--prune=all\b'; then
  echo '{"decision":"block","reason":"[guardrail] brew cleanup --prune=all is blocked — deletes all cached versions. Run manually if intentional."}'
  exit 2
fi

exit 0
