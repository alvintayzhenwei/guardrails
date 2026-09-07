#!/usr/bin/env bash
# =============================================================================
# Guardrails bootstrap for Claude Code.
# Resolves the hook library from: (1) $CLAUDE_GUARDRAILS_HOME, (2) sibling
# checkout, (3) per-user cache, (4) auto-clone. Fails open — never blocks Claude.
# Commit this file to your project at .claude/hooks/run-hooks.sh
#
# DISCLAIMER — NO WARRANTY, NO LIABILITY
# These hooks are ONE LAYER OF DEFENCE, NOT A SOLUTION, and are NOT FOOLPROOF.
# They are pattern matching over the text of a tool call: they will not catch
# every destructive command and are not intended to. They are not a sandbox,
# not access control, and NOT A SUBSTITUTE FOR BACKUPS, server-side branch
# protection, or reviewing what an agent does.
#
# This script FAILS OPEN: if the library cannot be resolved it exits 0 and the
# session continues WITH NO PROTECTION AT ALL. The absence of a block therefore
# NEVER means a command was checked and approved.
#
# Provided "as is" under the MIT License, without warranty of any kind and with
# no liability for any claim or damages. The entire risk of use is yours.
# Full terms: https://github.com/alvintayzhenwei/guardrails/blob/main/DISCLAIMER.md
# =============================================================================

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

# Fail open — never block Claude Code if the hooks are unreachable.
# Say so unmistakably: a user who believes they are protected and is not is
# worse off than one who knows they have no guardrails at all.
echo "[guardrails] ============================================================" >&2
echo "[guardrails] WARNING: hook library unavailable — THIS SESSION IS" >&2
echo "[guardrails] UNGUARDED. No command will be checked or refused." >&2
echo "[guardrails] Nothing being blocked does NOT mean anything is safe." >&2
echo "[guardrails] ------------------------------------------------------------" >&2
echo "[guardrails] Check network access to: $REPO_URL" >&2
echo "[guardrails] Or set CLAUDE_GUARDRAILS_HOME to a local checkout." >&2
echo "[guardrails] ============================================================" >&2
exit 0
