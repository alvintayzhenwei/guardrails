#!/bin/bash
# =============================================================================
# Check: production-destructive SQL and prod-host commands
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
# Set PROD_HOST_PATTERN to also block commands targeting prod hosts.
#
# The command is normalised before matching so the guard sees the SQL the
# database will see:
#   1. read-only search commands (grep/rg/...) are exempt — searching for the
#      phrase "DROP TABLE" is not running it
#   2. SQL comments are stripped, so a trailing `-- WHERE ...` cannot fake scope
#   3. newlines collapse to spaces, so multi-line SQL cannot split a keyword pair
#   4. statements are evaluated one per `;`, so a WHERE in a later statement
#      cannot vouch for an unscoped DELETE in an earlier one
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

CMD="$HOOK_COMMAND"

block() {
  printf '{"decision":"block","reason":"[guardrail] %s"}\n' "$1"
  exit 2
}

# ── 1. Read-only searches are not executions ────────────────────────────────
# Only when the search is the whole command — a chained `grep x && psql -c ...`
# still gets inspected.
if printf '%s' "$CMD" | grep -qE '^[[:space:]]*(grep|egrep|fgrep|rg|ag|ack|ripgrep)([[:space:]]|$)' && \
   ! printf '%s' "$CMD" | grep -qE ';|&&|\|\||\|'; then
  exit 0
fi
if printf '%s' "$CMD" | grep -qE '^[[:space:]]*git[[:space:]]+grep([[:space:]]|$)' && \
   ! printf '%s' "$CMD" | grep -qE ';|&&|\|\||\|'; then
  exit 0
fi

# ── 2-3. Normalise: strip comments, uppercase, flatten to one line ──────────
SQL=$(printf '%s' "$CMD" \
  | sed 's|/\*[^*]*\*/| |g' \
  | sed 's|--[^-].*$| |' \
  | tr '[:lower:]' '[:upper:]' \
  | tr '\n\r\t' '   ')

# ── 4. Evaluate each statement independently ────────────────────────────────
# has_real_scope <statement> — true only for a WHERE that actually narrows rows.
has_real_scope() {
  printf '%s' "$1" | grep -qE 'WHERE' || return 1
  # A tautological WHERE is no scope at all.
  if printf '%s' "$1" | grep -qE "WHERE[[:space:]]+\(?[[:space:]]*(TRUE|1[[:space:]]*=[[:space:]]*1|[0-9]+[[:space:]]*=[[:space:]]*[0-9]+|'[^']*'[[:space:]]*=[[:space:]]*'[^']*')"; then
    return 1
  fi
  return 0
}

OLD_IFS="$IFS"
IFS=';'
read -ra STATEMENTS <<< "$SQL"
IFS="$OLD_IFS"

for S in "${STATEMENTS[@]}"; do
  [ -z "$S" ] && continue

  if printf '%s' "$S" | grep -qE 'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)'; then
    block 'DROP TABLE / DATABASE / SCHEMA blocked. Run the SQL manually if intentional.'
  fi

  # TRUNCATE is unscoped by definition; the TABLE keyword is optional in
  # PostgreSQL and MySQL, so it is not required here either.
  if printf '%s' "$S" | grep -qE 'TRUNCATE([[:space:]]+TABLE)?[[:space:]]+["`'"'"'A-Z0-9_.]'; then
    block 'TRUNCATE blocked — it empties the table unconditionally. Run the SQL manually if intentional.'
  fi

  if printf '%s' "$S" | grep -qE 'DELETE[[:space:]]+FROM' && ! has_real_scope "$S"; then
    block 'DELETE FROM without a row-narrowing WHERE blocked — would delete all rows (a tautology such as WHERE 1=1 does not count). Run manually to confirm scope.'
  fi

  # The table name is matched as one opaque token, so a schema-qualified,
  # quoted or backslash-escaped name (public.users, "users", \"users\") is
  # recognised the same as a bare one.
  if printf '%s' "$S" | grep -qE 'UPDATE[[:space:]]+[^[:space:]]+[[:space:]]+SET' && ! has_real_scope "$S"; then
    block 'UPDATE SET without a row-narrowing WHERE blocked — would update all rows (a tautology such as WHERE 1=1 does not count). Run manually to confirm scope.'
  fi
done

# ── Optional production-host guard ──────────────────────────────────────────
if [ -n "$PROD_HOST_PATTERN" ]; then
  if printf '%s' "$CMD" | grep -qiE "$PROD_HOST_PATTERN"; then
    block 'Command targets a production host. Run manually if intentional.'
  fi
fi

exit 0
