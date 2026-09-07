#!/bin/bash
# =============================================================================
# Check: block writes to sensitive files
# Env: HOOK_TOOL_NAME, HOOK_FILE_PATH
#
# Matching is case-insensitive: macOS and Windows filesystems are, so `.ENV`
# and `.env` are the same file and must be treated the same way.
# Template files (.example/.sample/.template) are exempt — they exist to be
# written, and hold placeholders rather than credentials.
# =============================================================================

case "$HOOK_TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit|Update|*Edit|*Write) ;;
  *) exit 0 ;;
esac

FILE="$(basename "$HOOK_FILE_PATH")"
LC="$(printf '%s' "$FILE" | tr '[:upper:]' '[:lower:]')"

block() {
  printf '{"decision":"block","reason":"[guardrail] %s: %s. %s"}\n' "$1" "$FILE" "$2"
  exit 2
}

# ── Templates and samples are meant to be written ───────────────────────────
case "$LC" in
  *.example|*.sample|*.template|*.stub|*.dist|*.default) exit 0 ;;
esac

# ── Environment files ───────────────────────────────────────────────────────
case "$LC" in
  .env|.env.*|*.env|.envrc)
    block 'Writes to environment files are blocked' 'Manage .env files manually.'
    ;;
esac

# ── Key and certificate material ────────────────────────────────────────────
case "$LC" in
  *.pem|*.key|*.p12|*.jks|*.pfx|*.pkcs12|*.ppk|*.kdbx|*.asc|*.gpg|*.keystore)
    block 'Writes to key/certificate files are blocked' 'Manage key material manually.'
    ;;
esac

# ── Credential stores ───────────────────────────────────────────────────────
case "$LC" in
  credentials|credentials.json|secrets.json|secrets.yaml|secrets.yml|keystore.*|secret.properties|.netrc|_netrc|.git-credentials|.npmrc|.pypirc|.htpasswd|.dockercfg|.docker-config.json)
    block 'Writes to credential files are blocked' 'Manage this file manually.'
    ;;
esac

# ── SSH private keys ────────────────────────────────────────────────────────
case "$LC" in
  *id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*)
    block 'Writes to SSH private key files are blocked' 'Manage key files manually.'
    ;;
esac

exit 0
