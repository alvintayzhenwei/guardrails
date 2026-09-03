#!/usr/bin/env bash
# Guardrails bootstrap for Claude Code.
# Resolves the hook library from: (1) $CLAUDE_GUARDRAILS_HOME, (2) sibling
# checkout, (3) per-user cache, (4) auto-clone. Fails open — never blocks Claude.
# Commit this file to your project at .claude/hooks/run-hooks.sh

HOOK_TYPE="${1:-pre}"
SCRIPT="pre-tool-use.sh"
[ "$HOOK_TYPE" = "post" ] && SCRIPT="post-tool-use.sh"

REPO_URL="${CLAUDE_GUARDRAILS_REPO:-https://github.com/alvintayzhenwei/guardrails.git}"
USER_CACHE="${CLAUDE_GUARDRAILS_CACHE:-$HOME/.claude/guardrails}"
TTL_MINUTES="${CLAUDE_GUARDRAILS_TTL:-1440}"

# .claude/hooks/run-hooks.sh -> ../../ = project root -> ../ = workspace root
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"

# 1. Explicit override — point at any local checkout
if [ -n "$CLAUDE_GUARDRAILS_HOME" ] && [ -f "$CLAUDE_GUARDRAILS_HOME/$SCRIPT" ]; then
  exec bash "$CLAUDE_GUARDRAILS_HOME/$SCRIPT"
fi

# 2. Sibling checkout in a multi-repo workspace
for name in guardrails claude-guardrails; do
  if [ -f "$PROJECT_ROOT/../$name/$SCRIPT" ]; then
    exec bash "$PROJECT_ROOT/../$name/$SCRIPT"
  fi
done

# 3. Per-user cache — refresh once per TTL window
if [ -d "$USER_CACHE" ]; then
  STAMP="$USER_CACHE/.last-update"
  if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mmin "+$TTL_MINUTES" 2>/dev/null)" ]; then
    git -C "$USER_CACHE" pull --quiet --ff-only 2>/dev/null && touch "$STAMP"
  fi
  [ -f "$USER_CACHE/$SCRIPT" ] && exec bash "$USER_CACHE/$SCRIPT"
fi

# 4. Auto-clone into the user cache (once per machine)
echo "[guardrails] Fetching hook library from $REPO_URL ..." >&2
if git clone --depth 1 "$REPO_URL" "$USER_CACHE" 2>/dev/null; then
  touch "$USER_CACHE/.last-update"
  [ -f "$USER_CACHE/$SCRIPT" ] && exec bash "$USER_CACHE/$SCRIPT"
fi

# Fail open — never block Claude Code if the hooks are unreachable
echo "[guardrails] WARNING: hook library unavailable — guardrails are INACTIVE." >&2
echo "[guardrails] Check network access to: $REPO_URL" >&2
echo "[guardrails] Or set CLAUDE_GUARDRAILS_HOME to a local checkout." >&2
exit 0
