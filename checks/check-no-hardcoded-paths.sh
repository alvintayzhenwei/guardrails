#!/bin/bash
# =============================================================================
# Check: No Hardcoded User Paths in .claude/ Assets — AUTO-CORRECT
# Env: HOOK_TOOL_NAME, HOOK_FILE_PATH, HOOK_INPUT_JSON
# =============================================================================

FILE_PATH="$HOOK_FILE_PATH"
TOOL_NAME="$HOOK_TOOL_NAME"

if ! echo "$FILE_PATH" | grep -qi '[\\/]\.claude[\\/]'; then
  exit 0
fi

if echo "$FILE_PATH" | grep -qi 'settings\.local\.json$'; then
  exit 0
fi

IS_SHELL=false; IS_MARKDOWN=false; IS_JSON=false
case "$FILE_PATH" in
  *.sh)   IS_SHELL=true ;;
  *.md)   IS_MARKDOWN=true ;;
  *.json) IS_JSON=true ;;
esac

if [ "$TOOL_NAME" = "Write" ]; then
  TOOL_INPUT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
    let buf='';
    process.stdin.on('data',c=>buf+=c);
    process.stdin.on('end',()=>{
      try{const d=JSON.parse(buf);console.log(d.tool_input?.content||'')}
      catch(e){console.log('')}
    });
  " 2>/dev/null)
else
  TOOL_INPUT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
    let buf='';
    process.stdin.on('data',c=>buf+=c);
    process.stdin.on('end',()=>{
      try{const d=JSON.parse(buf);console.log((d.tool_input?.old_string||'')+' '+(d.tool_input?.new_string||''))}
      catch(e){console.log('')}
    });
  " 2>/dev/null)
fi

MATCHES=""

while IFS= read -r m; do
  [ -n "$m" ] && MATCHES="${MATCHES}${m}"$'\n'
done < <(echo "$TOOL_INPUT" | grep -oiE '[A-Za-z]:[/\\]+Users[/\\]+[A-Za-z0-9_.@-]+[/\\][^"\\,})]+' 2>/dev/null)

while IFS= read -r m; do
  [ -n "$m" ] && MATCHES="${MATCHES}${m}"$'\n'
done < <(echo "$TOOL_INPUT" | grep -oE '/home/[a-zA-Z0-9_]+/[^"\\,})*]+' 2>/dev/null)

while IFS= read -r m; do
  [ -n "$m" ] && MATCHES="${MATCHES}${m}"$'\n'
done < <(echo "$TOOL_INPUT" | grep -oE '/Users/[a-zA-Z0-9_]+/[^"\\,})*]+' 2>/dev/null)

while IFS= read -r m; do
  [ -n "$m" ] && {
    if ! echo "$m" | grep -qiE '[A-Za-z]:[/\\]+Users[/\\]'; then
      MATCHES="${MATCHES}${m}"$'\n'
    fi
  }
done < <(echo "$TOOL_INPUT" | grep -oE '[A-Za-z]:[/\\]+[A-Za-z0-9_.-]+[/\\]+[A-Za-z0-9_.-]+[/\\]+[A-Za-z0-9_./-]+' 2>/dev/null | grep -v '://')

MATCHES=$(echo "$MATCHES" | sort -u | sed '/^$/d')
[ -z "$MATCHES" ] && exit 0

echo "" >&2
echo "================================================================" >&2
echo "  AUTO-CORRECT: Hardcoded paths in shared .claude/ asset" >&2
echo "================================================================" >&2
echo "" >&2
echo "  File: $FILE_PATH" >&2
echo "" >&2
echo "  Please retry with these replacements applied:" >&2
echo "----------------------------------------------------------------" >&2

while IFS= read -r FOUND_PATH; do
  [ -z "$FOUND_PATH" ] && continue
  AFTER_CLAUDE=""
  echo "$FOUND_PATH" | grep -qi '[\\/]\.claude[\\/]' \
    && AFTER_CLAUDE=$(echo "$FOUND_PATH" | sed -n 's|.*[/\\]\.claude[/\\]||Ip')

  REPLACEMENT=""
  if $IS_SHELL; then
    if [ -n "$AFTER_CLAUDE" ]; then
      echo "$AFTER_CLAUDE" | grep -q '^hooks/' \
        && REPLACEMENT="\$SCRIPT_DIR/$(echo "$AFTER_CLAUDE" | sed 's|^hooks/||')" \
        || REPLACEMENT="\$SCRIPT_DIR/../${AFTER_CLAUDE}"
    else
      REPLACEMENT="\$(git rev-parse --show-toplevel)"
    fi
  elif $IS_MARKDOWN || $IS_JSON; then
    if [ -n "$AFTER_CLAUDE" ]; then
      REPLACEMENT=".claude/${AFTER_CLAUDE}"
    else
      REPLACEMENT=$(echo "$FOUND_PATH" | sed 's|^[A-Za-z]:[/\\]*||; s|^/home/[^/]*/||; s|^/Users/[^/]*/||')
    fi
  else
    [ -n "$AFTER_CLAUDE" ] && REPLACEMENT=".claude/${AFTER_CLAUDE}" || REPLACEMENT="<use-relative-path>"
  fi

  echo "" >&2
  echo "  FOUND  : $FOUND_PATH" >&2
  echo "  REPLACE: $REPLACEMENT" >&2
done <<< "$MATCHES"

echo "" >&2
echo "----------------------------------------------------------------" >&2
$IS_SHELL && echo '  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"' >&2
($IS_MARKDOWN || $IS_JSON) && echo "  Use paths relative to repo root: .claude/hooks/..." >&2
echo "" >&2
echo "  Apply replacements and retry (auto-correction)." >&2
echo "================================================================" >&2

exit 2
