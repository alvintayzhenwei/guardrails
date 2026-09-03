#!/bin/bash
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

# Anchor to flag tokens (start with [space]-) so filenames like block-rm-rf.sh don't match.
# Block: combined -rf/-fr flag token, or separate -r and -f flag tokens.
COMBINED=$(echo "$HOOK_COMMAND" | grep -ciE '[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*[fF]|[[:space:]]-[a-zA-Z]*[fF][a-zA-Z]*[rR]')
HAS_R=$(echo "$HOOK_COMMAND" | grep -ciE '[[:space:]]-[a-zA-Z]*[rR]([[:space:]]|$)')
HAS_F=$(echo "$HOOK_COMMAND" | grep -ciE '[[:space:]]-[a-zA-Z]*[fF]([[:space:]]|$)')
if echo "$HOOK_COMMAND" | grep -qiE 'rm[[:space:]]' && \
   ( [ "$COMBINED" -gt 0 ] || ( [ "$HAS_R" -gt 0 ] && [ "$HAS_F" -gt 0 ] ) ); then
  echo '{"decision":"block","reason":"[guardrail] rm -rf commands are not allowed. Remove files manually if intentional."}'
  exit 2
fi

# PowerShell: Remove-Item or ri alias with both -Recurse and -Force (any order, any short-form)
if echo "$HOOK_COMMAND" | grep -qiE '(^|[[:space:]])(Remove-Item|ri)[[:space:]]'; then
  PS_HAS_RECURSE=$(echo "$HOOK_COMMAND" | grep -ciE '[[:space:]]-Recurse([[:space:]]|:|$)|[[:space:]]-r([[:space:]]|:|$)')
  PS_HAS_FORCE=$(echo "$HOOK_COMMAND" | grep -ciE '[[:space:]]-Force([[:space:]]|:|$)|[[:space:]]-fo([[:space:]]|:|$)')
  if [ "$PS_HAS_RECURSE" -gt 0 ] && [ "$PS_HAS_FORCE" -gt 0 ]; then
    echo '{"decision":"block","reason":"[guardrail] Remove-Item -Recurse -Force is not allowed. Remove files manually if intentional."}'
    exit 2
  fi
fi

# PowerShell/CMD: rmdir /S /Q (recursive force-delete)
if echo "$HOOK_COMMAND" | grep -qiE 'rmdir[[:space:]]' && \
   echo "$HOOK_COMMAND" | grep -qiE '/[Ss]([[:space:]]|$)' && \
   echo "$HOOK_COMMAND" | grep -qiE '/[Qq]([[:space:]]|$)'; then
  echo '{"decision":"block","reason":"[guardrail] rmdir /S /Q is not allowed. Remove directories manually if intentional."}'
  exit 2
fi

exit 0
