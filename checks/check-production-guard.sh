#!/bin/bash
# =============================================================================
# Check: Production-destructive SQL and prod-host commands
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
# Set PROD_HOST_PATTERN env var to also block commands targeting prod hosts.
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

CMD_UPPER=$(echo "$HOOK_COMMAND" | tr '[:lower:]' '[:upper:]')

if echo "$CMD_UPPER" | grep -qE 'DROP[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE'; then
  echo '{"decision":"block","reason":"[guardrail] DROP TABLE / TRUNCATE TABLE blocked. Run the SQL manually if intentional."}'
  exit 2
fi

if echo "$CMD_UPPER" | grep -qE 'DELETE[[:space:]]+FROM' && ! echo "$CMD_UPPER" | grep -qE 'WHERE'; then
  echo '{"decision":"block","reason":"[guardrail] DELETE FROM without WHERE blocked — would delete all rows. Run manually to confirm scope."}'
  exit 2
fi

if echo "$CMD_UPPER" | grep -qE 'UPDATE[[:space:]]+[A-Z0-9_]+[[:space:]]+SET' && ! echo "$CMD_UPPER" | grep -qE 'WHERE'; then
  echo '{"decision":"block","reason":"[guardrail] UPDATE SET without WHERE blocked — would update all rows. Run manually to confirm scope."}'
  exit 2
fi

if [ -n "$PROD_HOST_PATTERN" ]; then
  if echo "$HOOK_COMMAND" | grep -qiE "$PROD_HOST_PATTERN"; then
    echo '{"decision":"block","reason":"[guardrail] Command targets a production host. Run manually if intentional."}'
    exit 2
  fi
fi

exit 0
