#!/bin/bash
# =============================================================================
# Check: Credential literals in Write/Edit content
# Env: HOOK_TOOL_NAME, HOOK_FILE_PATH, HOOK_INPUT_JSON
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Write" ] && [ "$HOOK_TOOL_NAME" != "Edit" ] && exit 0

FP="$HOOK_FILE_PATH"

case "$FP" in
  */.claude/*|*\.claude/*) exit 0 ;;
  */test/*|*/__tests__/*|*/fixtures/*|*/testdata/*) exit 0 ;;
esac
case "$(basename "$FP")" in
  *.example|*.template|*.sample|*.stub) exit 0 ;;
esac

if [ "$HOOK_TOOL_NAME" = "Write" ]; then
  CONTENT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
    let b=''; process.stdin.on('data',c=>b+=c);
    process.stdin.on('end',()=>{
      try{const d=JSON.parse(b);process.stdout.write(d.tool_input?.content||'')}
      catch(e){process.stdout.write('')}
    });
  " 2>/dev/null)
else
  CONTENT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
    let b=''; process.stdin.on('data',c=>b+=c);
    process.stdin.on('end',()=>{
      try{const d=JSON.parse(b);process.stdout.write(d.tool_input?.new_string||'')}
      catch(e){process.stdout.write('')}
    });
  " 2>/dev/null)
fi

[ -z "$CONTENT" ] && exit 0

FOUND=""

echo "$CONTENT" | grep -qiE 'password[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{4,}' \
  && FOUND="${FOUND:+$FOUND, }password literal"

echo "$CONTENT" | grep -qiE '(secret|api_key|apikey|api_secret|client_secret)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"']{8,}' \
  && FOUND="${FOUND:+$FOUND, }secret/api_key literal"

echo "$CONTENT" | grep -qiE -- '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' \
  && FOUND="${FOUND:+$FOUND, }private key block"

echo "$CONTENT" | grep -qE 'Bearer [A-Za-z0-9._-]{20,}' \
  && FOUND="${FOUND:+$FOUND, }Bearer token"

echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}' \
  && FOUND="${FOUND:+$FOUND, }AWS access key"

if [ -n "$FOUND" ]; then
  FILE_NAME="$(basename "$FP")"
  echo "{\"decision\":\"block\",\"reason\":\"[guardrail] Credential literal detected ($FOUND) in $FILE_NAME. Use an environment variable reference (e.g. \${DB_PASSWORD}) instead of a literal value.\"}"
  exit 2
fi

exit 0
