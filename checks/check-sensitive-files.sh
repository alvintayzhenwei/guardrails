#!/bin/bash
# =============================================================================
# Check: Block writes to sensitive files
# Env: HOOK_TOOL_NAME, HOOK_FILE_PATH
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Write" ] && [ "$HOOK_TOOL_NAME" != "Edit" ] && exit 0

FILE="$(basename "$HOOK_FILE_PATH")"

case "$FILE" in
  .env|.env.*)
    echo "{\"decision\":\"block\",\"reason\":\"[guardrail] Writes to environment files are blocked: $FILE. Manage .env files manually.\"}"
    exit 2
    ;;
esac

case "$FILE" in
  *.pem|*.key|*.p12|*.jks|*.pfx|*.pkcs12)
    echo "{\"decision\":\"block\",\"reason\":\"[guardrail] Writes to key/certificate files are blocked: $FILE. Manage key material manually.\"}"
    exit 2
    ;;
esac

case "$FILE" in
  credentials.json|secrets.json|keystore.*|secret.properties)
    echo "{\"decision\":\"block\",\"reason\":\"[guardrail] Writes to credential files are blocked: $FILE. Manage this file manually.\"}"
    exit 2
    ;;
esac

case "$FILE" in
  *id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*)
    echo "{\"decision\":\"block\",\"reason\":\"[guardrail] Writes to SSH private key files are blocked: $FILE. Manage key files manually.\"}"
    exit 2
    ;;
esac

exit 0
