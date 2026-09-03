#!/bin/bash
# =============================================================================
# Shared Post-Tool-Use Dispatcher
# After Write|Edit: auto-classifies any new MCP servers found in settings files.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(pwd)"

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | node -e "
  let b=''; process.stdin.on('data',c=>b+=c);
  process.stdin.on('end',()=>{
    try { const d=JSON.parse(b); process.stdout.write(d.tool_name||''); }
    catch(e) {}
  });
" 2>/dev/null)

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

REGISTRY="$PROJECT_ROOT/.claude/hooks/mcp-registry.json"
GUARDRAIL="$SCRIPT_DIR/checks/check-mcp-guardrail.sh"

[ ! -f "$REGISTRY" ] && exit 0

node "$SCRIPT_DIR/mcp-classify.js" \
  "$REGISTRY" \
  "$GUARDRAIL" \
  "$PROJECT_ROOT" \
  "$HOME/.claude/settings.json" \
  2>&2

exit 0
