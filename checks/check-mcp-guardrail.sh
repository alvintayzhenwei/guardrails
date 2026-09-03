#!/bin/bash
# =============================================================================
# Check: MCP Outbound Data Guardrail
# Env: HOOK_TOOL_NAME, HOOK_INPUT_JSON, HOOK_PROJECT_ROOT
#
# LOCAL MCPs (in mcp-registry.json) → exit 0 silently
# EXTERNAL MCPs → display payload review banner, allow Allow/Deny consent prompt
# =============================================================================

TOOL_NAME="$HOOK_TOOL_NAME"
SETTINGS_FILE="$HOOK_PROJECT_ROOT/.claude/settings.local.json"
REGISTRY_FILE="$HOOK_PROJECT_ROOT/.claude/hooks/mcp-registry.json"

MCP_SERVER=$(echo "$TOOL_NAME" | sed -n 's/^mcp__\(.*\)__[^_]*$/\1/p' | sed 's/_/ /g')
MCP_METHOD=$(echo "$TOOL_NAME" | sed -n 's/^mcp__.*__\(.*\)$/\1/p')
[ -z "$MCP_SERVER" ] && MCP_SERVER="unknown"
[ -z "$MCP_METHOD" ] && MCP_METHOD="$TOOL_NAME"

# Check registry to skip LOCAL MCPs
if [ -f "$REGISTRY_FILE" ]; then
  IS_LOCAL=$(node -e "
    const fs = require('fs');
    try {
      const reg = JSON.parse(fs.readFileSync('$REGISTRY_FILE', 'utf8'));
      const local = Object.keys(reg.local || {});
      const tool = '$TOOL_NAME';
      process.stdout.write(local.some(p => tool.startsWith(p)) ? 'yes' : 'no');
    } catch(e) { process.stdout.write('no'); }
  " 2>/dev/null)
  [ "$IS_LOCAL" = "yes" ] && exit 0
fi

# Auto-remove from permissions.allow so consent prompt always fires
MCP_PREFIX=$(echo "$TOOL_NAME" | sed -n 's/^\(mcp__.*__\).*/\1/p')

if [ -f "$SETTINGS_FILE" ] && [ -n "$MCP_PREFIX" ]; then
  if grep -q "\"${MCP_PREFIX}" "$SETTINGS_FILE" 2>/dev/null; then
    node -e "
      const fs = require('fs');
      const f = '$SETTINGS_FILE';
      const prefix = '$MCP_PREFIX';
      const cfg = JSON.parse(fs.readFileSync(f, 'utf8'));
      if (cfg.permissions && Array.isArray(cfg.permissions.allow)) {
        const before = cfg.permissions.allow.length;
        cfg.permissions.allow = cfg.permissions.allow.filter(e => !e.startsWith(prefix));
        const removed = before - cfg.permissions.allow.length;
        if (removed > 0) {
          fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + '\n');
          process.stderr.write('\n  MCP GUARDRAIL: Auto-removed ' + removed + ' entry matching \"' + prefix + '*\" from permissions.allow.\n\n');
        }
      }
    " 2>&2
  fi
fi

SERVICE_DESC="MCP server [$MCP_SERVER] — verify if this is an external service"
case "$TOOL_NAME" in
  mcp__plugin_context7_context7__*)
    SERVICE_DESC="Context7 cloud API (context7.com) — library documentation service"
    ;;
esac

TOOL_INPUT=$(printf '%s' "$HOOK_INPUT_JSON" | node -e "
  let b=''; process.stdin.on('data',c=>b+=c);
  process.stdin.on('end',()=>{
    try {
      const d = JSON.parse(b);
      process.stdout.write(JSON.stringify(d.tool_input||{}, null, 2));
    } catch(e) { process.stdout.write('{}'); }
  });
" 2>/dev/null)

echo "" >&2
echo "================================================================" >&2
echo "  MCP OUTBOUND DATA REVIEW" >&2
echo "================================================================" >&2
echo "  Risk Level : EXTERNAL" >&2
echo "  MCP Server : $MCP_SERVER" >&2
echo "  Method     : $MCP_METHOD" >&2
echo "  Service    : $SERVICE_DESC" >&2
echo "" >&2
echo "  OUTBOUND PAYLOAD:" >&2
echo "$TOOL_INPUT" | head -20 >&2
echo "" >&2
echo "  Data leaves your machine. Use Allow/Deny prompt to approve." >&2
echo "================================================================" >&2
echo "" >&2

exit 0
