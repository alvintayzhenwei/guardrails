#!/bin/bash
# =============================================================================
# Check: credential literals in written content
# Env: HOOK_TOOL_NAME, HOOK_FILE_PATH, HOOK_INPUT_JSON
#
# Covers every write-shaped tool, not just Write/Edit — a guard that only knows
# two tool names stops guarding the moment a third one appears.
# Content is read from whichever field the tool uses (content, new_string,
# new_source, or the edits[] array of a batch edit).
# =============================================================================

case "$HOOK_TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit|Update|*Edit|*Write) ;;
  *) exit 0 ;;
esac

FP="$HOOK_FILE_PATH"

# ── Exempt paths ────────────────────────────────────────────────────────────
# .claude/ holds the guardrail config itself, which names credential patterns.
# Test and fixture trees hold deliberate dummy values. Both match on full path
# segments only, so `latest/` and `.claudette/` are NOT exempt.
case "/$FP/" in
  */.claude/*) exit 0 ;;
  */test/*|*/tests/*|*/__tests__/*|*/spec/*|*/fixtures/*|*/testdata/*) exit 0 ;;
esac
case "$(basename "$FP")" in
  *.example|*.sample|*.template|*.stub|*.dist) exit 0 ;;
esac

# ── Pull the written content out of whatever field carries it ───────────────
CONTENT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
  let b=''; process.stdin.on('data',c=>b+=c);
  process.stdin.on('end',()=>{
    try {
      const i = (JSON.parse(b).tool_input) || {};
      const parts = [i.content, i.new_string, i.new_source, i.text];
      if (Array.isArray(i.edits)) for (const e of i.edits) parts.push(e && e.new_string);
      if (Array.isArray(i.new_source)) parts.push(i.new_source.join('\n'));
      process.stdout.write(parts.filter(p => typeof p === 'string').join('\n'));
    } catch(e) { process.stdout.write(''); }
  });
" 2>/dev/null)

[ -z "$CONTENT" ] && exit 0

FOUND=""
add() { FOUND="${FOUND:+$FOUND, }$1"; }

# printf, not echo — echo mangles backslashes in some shells, and key material
# is exactly where that matters.
# -e is required: several patterns below start with "-" and would otherwise be
# parsed as grep options.
scan() { printf '%s\n' "$CONTENT" | grep -qE -e "$1"; }
scan_i() { printf '%s\n' "$CONTENT" | grep -qiE -e "$1"; }

Q="[\"']"

# ── Quoted credential assignments ───────────────────────────────────────────
scan_i "password[[:space:]]*[=:][[:space:]]*${Q}[^\"']{4,}" && add 'password literal'
scan_i "(secret|api_key|apikey|api_secret|client_secret|auth_token|access_token)[[:space:]]*[=:][[:space:]]*${Q}[^\"']{8,}" \
  && add 'secret/api_key literal'

# ── Unquoted credential assignments (env-file and shell style) ──────────────
# A reference to a variable, environment lookup or template placeholder is the
# correct pattern and stays allowed.
if ! scan_i 'environ|getenv|process\.env|secretsmanager|vault|\$\{|\$[A-Za-z_]|<%|\{\{'; then
  scan_i '(password|passwd|pwd)[a-z_]*[[:space:]]*=[[:space:]]*[A-Za-z0-9._/+-]{4,}[[:space:]]*$' \
    && add 'unquoted password assignment'
fi

# ── Private key blocks ──────────────────────────────────────────────────────
scan '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY( BLOCK)?-----' && add 'private key block'

# ── Provider-specific token formats ─────────────────────────────────────────
scan 'Bearer [A-Za-z0-9._-]{20,}'            && add 'Bearer token'
scan '(AKIA|ASIA)[0-9A-Z]{16}'               && add 'AWS access key'
scan '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' && add 'GitHub token'
scan 'github_pat_[A-Za-z0-9_]{20,}'          && add 'GitHub fine-grained token'
scan 'xox[baprs]-[A-Za-z0-9-]{10,}'          && add 'Slack token'
scan 'AIza[0-9A-Za-z_-]{30,}'                && add 'Google API key'
scan '(sk|rk)_live_[0-9A-Za-z]{16,}'         && add 'Stripe live key'
scan 'glpat-[A-Za-z0-9_-]{16,}'              && add 'GitLab token'
scan 'npm_[A-Za-z0-9]{30,}'                  && add 'npm token'
scan 'sk-(proj-)?[A-Za-z0-9_-]{32,}'         && add 'OpenAI-style API key'
scan 'sk-ant-[A-Za-z0-9_-]{20,}'             && add 'Anthropic API key'

if [ -n "$FOUND" ]; then
  printf '{"decision":"block","reason":"[guardrail] Credential literal detected (%s) in %s. Use an environment variable reference (e.g. ${DB_PASSWORD}) instead of a literal value."}\n' \
    "$FOUND" "$(basename "$FP")"
  exit 2
fi

exit 0
