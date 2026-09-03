#!/bin/bash
# =============================================================================
# Shared Pre-Tool-Use Dispatcher
# Reads JSON payload once, exports env vars, runs each applicable check.
# First check to exit 2 blocks the tool call and terminates the chain.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
PROJECT_ROOT="$(pwd)"
SKIP_FILE="$PROJECT_ROOT/.claude/hooks-skip.json"

INPUT=$(cat)

eval "$(printf '%s' "$INPUT" | node -e "
  let b=''; process.stdin.on('data',c=>b+=c);
  process.stdin.on('end',()=>{
    try {
      const d = JSON.parse(b);
      const t = d.tool_name || '';
      const i = d.tool_input || {};
      const fp = (i.file_path || i.path || '').replace(/\\\\/g, '/');
      const cmd = i.command || '';
      process.stdout.write('HOOK_TOOL_NAME=' + JSON.stringify(t) + '\n');
      process.stdout.write('HOOK_FILE_PATH=' + JSON.stringify(fp) + '\n');
      process.stdout.write('HOOK_COMMAND=' + JSON.stringify(cmd) + '\n');
    } catch(e) { process.exit(0); }
  });
" 2>/dev/null)"

export HOOK_TOOL_NAME
export HOOK_FILE_PATH
export HOOK_COMMAND
export HOOK_INPUT_JSON="$INPUT"
export HOOK_PROJECT_ROOT="$PROJECT_ROOT"

[ -z "$HOOK_TOOL_NAME" ] && exit 0

should_skip() {
  [ -f "$SKIP_FILE" ] && grep -q "\"$1\"" "$SKIP_FILE" 2>/dev/null
}

run_check() {
  local script="$CHECKS_DIR/${1}.sh"
  [ ! -f "$script" ] && return 0
  should_skip "$1" && return 0
  bash "$script"
  [ $? -eq 2 ] && exit 2
}

case "$HOOK_TOOL_NAME" in
  Bash)
    run_check "check-rm-rf"
    run_check "check-dangerous-git"
    run_check "check-production-guard"
    run_check "check-macos-destructive"
    run_check "check-homebrew"
    ;;
  PowerShell)
    run_check "check-rm-rf"
    run_check "check-dangerous-git"
    run_check "check-production-guard"
    ;;
  Write|Edit)
    run_check "check-sensitive-files"
    run_check "check-secrets-write"
    run_check "check-no-hardcoded-paths"
    ;;
  mcp__*)
    run_check "check-mcp-guardrail"
    ;;
esac

exit 0
