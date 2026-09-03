#!/usr/bin/env bash
# Install the pre-push guard into a repo's git hooks directory.
# Usage: bash git-hooks/install.sh [<repo-path>]   (default: current repo)
# Idempotent — re-run to update.

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SRC_DIR/pre-push"
TARGET_REPO="${1:-$PWD}"
MARKER="guardrails-pre-push"

[ -f "$SRC" ] || { echo "[guardrails] Missing source hook: $SRC" >&2; exit 1; }

GIT_DIR="$(git -C "$TARGET_REPO" rev-parse --git-common-dir 2>/dev/null)" || {
  echo "[guardrails] Not a git repository: $TARGET_REPO" >&2
  exit 1
}
case "$GIT_DIR" in
  /*|[A-Za-z]:[/\]*) ;;
  *) GIT_DIR="$TARGET_REPO/$GIT_DIR" ;;
esac

# husky and friends set core.hooksPath, which makes .git/hooks/* dead files.
# Install where git will actually look, or the guard is a silent no-op.
CUSTOM="$(git -C "$TARGET_REPO" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$CUSTOM" ]; then
  case "$CUSTOM" in
    /*|[A-Za-z]:[/\]*) HOOK_DIR="$CUSTOM" ;;
    *) HOOK_DIR="$TARGET_REPO/$CUSTOM" ;;
  esac
  echo "[guardrails] core.hooksPath=$CUSTOM — installing there, not .git/hooks"
else
  HOOK_DIR="$GIT_DIR/hooks"
fi

mkdir -p "$HOOK_DIR"
DEST="$HOOK_DIR/pre-push"

if [ -f "$DEST" ] && ! grep -q "$MARKER" "$DEST" 2>/dev/null; then
  mv "$DEST" "$HOOK_DIR/pre-push.local"
  chmod +x "$HOOK_DIR/pre-push.local" 2>/dev/null || true
  echo "[guardrails] Existing pre-push hook preserved as pre-push.local"
  echo "[guardrails] It still runs — after the guard passes."
fi

cp "$SRC" "$DEST"
chmod +x "$DEST"

echo "[guardrails] pre-push guard installed: $DEST"
echo "[guardrails] Protected: ${GUARDRAILS_PROTECTED_BRANCHES:-main master}"
