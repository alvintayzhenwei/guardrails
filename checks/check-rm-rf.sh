#!/bin/bash
# =============================================================================
# Check: recursive force-delete, in every spelling
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
#
# Flag detection is token-anchored (a flag starts after whitespace with "-") so
# a filename like block-rm-rf.sh never matches, and covers short, combined,
# uppercase and GNU long forms -- `rm -rf`, `rm -fr`, `rm -R -f` and
# `rm --recursive --force` are the same command and are treated as such.
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

CMD="$HOOK_COMMAND"

block() {
  printf '{"decision":"block","reason":"[guardrail] %s"}\n' "$1"
  exit 2
}

# A command word: preceded by start-of-line or a non-word character, so
# `/bin/rm`, `\rm`, `sudo rm`, `; rm` and `"rm` all count but `perform ` does not.
cmd_word() { printf '%s' "$CMD" | grep -qE "(^|[^A-Za-z0-9_.-])$1([[:space:]]|$)"; }

# A short flag token carrying any of the given letters, e.g. short_flag 'rR'
# matches " -r", " -rf", " -vr" but never " --recursive".
short_flag() { printf '%s' "$CMD" | grep -qE "[[:space:]]-[a-zA-Z]*[$1][a-zA-Z]*([[:space:]]|$)"; }

# A GNU long flag, with or without an =value.
long_flag() { printf '%s' "$CMD" | grep -qiE "[[:space:]]--$1([[:space:]=]|$)"; }

# ── POSIX rm ────────────────────────────────────────────────────────────────
if cmd_word 'rm'; then
  RECURSIVE=false; FORCE=false
  short_flag 'rR' && RECURSIVE=true
  long_flag 'recursive' && RECURSIVE=true
  short_flag 'fF' && FORCE=true
  long_flag 'force' && FORCE=true

  if $RECURSIVE && $FORCE; then
    block 'rm -rf commands are not allowed (including --recursive/--force long forms). Remove files manually if intentional.'
  fi
fi

# ── find -delete: a recursive delete that never spells out rm ───────────────
if cmd_word 'find' && printf '%s' "$CMD" | grep -qE '[[:space:]]-delete([[:space:]]|$)'; then
  block 'find -delete is not allowed — it deletes every match recursively. Run manually if intentional.'
fi

# ── PowerShell Remove-Item and its aliases ──────────────────────────────────
# ri, rd, rmdir, del and erase are all aliases of Remove-Item in PowerShell.
if printf '%s' "$CMD" | grep -qiE '(^|[[:space:]])(Remove-Item|ri|rd|rmdir|del|erase)[[:space:]]'; then
  PS_RECURSE=false; PS_FORCE=false
  printf '%s' "$CMD" | grep -qiE '[[:space:]]-(Recurse|r)([[:space:]]|:|$)' && PS_RECURSE=true
  printf '%s' "$CMD" | grep -qiE '[[:space:]]-(Force|fo|f)([[:space:]]|:|$)' && PS_FORCE=true

  if $PS_RECURSE && $PS_FORCE; then
    block 'Remove-Item -Recurse -Force is not allowed (including the ri/rd/rmdir/del/erase aliases). Remove files manually if intentional.'
  fi
fi

# ── cmd.exe style recursive quiet delete ────────────────────────────────────
if printf '%s' "$CMD" | grep -qiE '(^|[[:space:]])(rmdir|rd|del|erase)[[:space:]]' && \
   printf '%s' "$CMD" | grep -qE '/[Ss]([[:space:]]|$)' && \
   printf '%s' "$CMD" | grep -qE '/[Qq]([[:space:]]|$)'; then
  block 'rmdir /S /Q is not allowed. Remove directories manually if intentional.'
fi

exit 0
