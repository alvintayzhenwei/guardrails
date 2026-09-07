#!/usr/bin/env bash
# =============================================================================
# Check: macOS-specific destructive operations
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
# Blocks diskutil erasure, secure-delete recursive, system launchctl bootout,
# and bare defaults delete (which wipes all user defaults).
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Bash" ] && exit 0

CMD="$HOOK_COMMAND"

if echo "$CMD" | grep -qiE 'diskutil[[:space:]]+(eraseDisk|eraseVolume|zeroDisk|secureErase|reformat)\b'; then
  echo '{"decision":"block","reason":"[guardrail] diskutil destructive operations are blocked. Run manually if intentional."}'
  exit 2
fi

# APFS container/volume deletion erases every volume inside the container.
if echo "$CMD" | grep -qiE 'diskutil[[:space:]]+(apfs|ap)[[:space:]]+(deleteContainer|deleteVolume|eraseVolume|eraseContainer)\b'; then
  echo '{"decision":"block","reason":"[guardrail] diskutil apfs deleteContainer/deleteVolume is blocked — erases every volume in the container. Run manually if intentional."}'
  exit 2
fi

if echo "$CMD" | grep -qiE '(^|[[:space:]]|/)srm[[:space:]]'; then
  if echo "$CMD" | grep -qiE '[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)|[[:space:]]--recursive([[:space:]]|=|$)'; then
    echo '{"decision":"block","reason":"[guardrail] srm -r is blocked — secure-deletes files recursively. Run manually if intentional."}'
    exit 2
  fi
fi

if echo "$CMD" | grep -qiE 'launchctl[[:space:]]+bootout[[:space:]]+system/'; then
  echo '{"decision":"block","reason":"[guardrail] launchctl bootout system/ is blocked — unloads system-level daemons. Run manually if intentional."}'
  exit 2
fi

if echo "$CMD" | grep -qE 'defaults[[:space:]]+delete[[:space:]]*(>|2>|;|&&|\|\||#|$)'; then
  echo '{"decision":"block","reason":"[guardrail] defaults delete (no domain) is blocked — wipes all user defaults. Use: defaults delete <domain> if intentional."}'
  exit 2
fi

exit 0
