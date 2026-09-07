#!/bin/bash
# =============================================================================
# Check: destructive git operations
# Env: HOOK_TOOL_NAME, HOOK_COMMAND
#
# Every rule matches through git's global options, so `git -c core.hooksPath=…
# push` and `git -C /repo reset --hard` are caught the same as the bare forms.
# Flags are matched case-SENSITIVELY where git's own meaning is case-dependent:
# `-d` (delete merged) is safe, `-D` (force delete) is not.
# =============================================================================

[ "$HOOK_TOOL_NAME" != "Bash" ] && [ "$HOOK_TOOL_NAME" != "PowerShell" ] && exit 0

CMD="$HOOK_COMMAND"

# git's global options, which may appear between `git` and the subcommand.
GIT_OPT='(-c[[:space:]]+[^[:space:]]+|-C[[:space:]]+[^[:space:]]+|--no-pager|--paginate|-p|--git-dir=[^[:space:]]*|--work-tree=[^[:space:]]*|--exec-path=[^[:space:]]*|--namespace=[^[:space:]]*|--literal-pathspecs|--no-replace-objects|--bare)'
GIT="(^|[^A-Za-z0-9_.-])git([[:space:]]+${GIT_OPT})*[[:space:]]+"

block() {
  printf '{"decision":"block","reason":"[guardrail] %s"}\n' "$1"
  exit 2
}

# sub <name> — is this git subcommand being invoked?
sub() { printf '%s' "$CMD" | grep -qiE "${GIT}$1([[:space:]]|$)"; }

# flag_ci <regex> / flag_cs <regex> — case-insensitive / case-sensitive flag token
flag_ci() { printf '%s' "$CMD" | grep -qiE "[[:space:]]-{1,2}$1([[:space:]=]|$)"; }
flag_cs() { printf '%s' "$CMD" | grep -qE "$1"; }

# A bare `.` pathspec argument — the "everything in the working tree" target.
bare_dot() { printf '%s' "$CMD" | grep -qE '[[:space:]]\.([[:space:]]|"|'"'"'|$)'; }

# ── push: always the developer's call ───────────────────────────────────────
if sub 'push'; then
  block 'git push is blocked. Push must be done manually by the developer.'
fi

# ── reset --hard: discards uncommitted work ─────────────────────────────────
if sub 'reset' && flag_ci 'hard'; then
  block 'git reset --hard is blocked — this discards uncommitted work. Run manually if intentional.'
fi

# ── branch deletion: -D / -d -f / --delete --force (but -d alone is safe) ───
if sub 'branch'; then
  if flag_cs '[[:space:]]-[a-zA-Z]*D([[:space:]]|$)' || \
     flag_cs '[[:space:]]--force([[:space:]]|=|$)' || \
     flag_cs '[[:space:]]-[a-z]*f([a-z]*)?([[:space:]]|$)'; then
    block 'git branch force-delete (-D / --delete --force) is blocked. Delete branches manually if intentional. `git branch -d` on a merged branch is allowed.'
  fi
fi

# ── clean -f: deletes untracked files ───────────────────────────────────────
if sub 'clean' && printf '%s' "$CMD" | grep -qE '[[:space:]]-{1,2}[a-zA-Z]*f'; then
  block 'git clean -f is blocked — this deletes untracked files. Run manually if intentional.'
fi

# ── checkout: discarding the working tree ───────────────────────────────────
if sub 'checkout'; then
  if bare_dot; then
    block 'git checkout . is blocked — this discards all working tree changes. Run manually if intentional.'
  fi
  if flag_cs '[[:space:]]--force([[:space:]]|=|$)' || flag_cs '[[:space:]]-[a-z]*f([[:space:]]|$)'; then
    block 'git checkout --force is blocked — this overwrites local modifications. Run manually if intentional.'
  fi
fi

# ── restore: the modern spelling of "discard my changes" ────────────────────
# `git restore --staged <path>` only unstages, so it stays allowed.
if sub 'restore'; then
  STAGED_ONLY=false
  if flag_ci 'staged' && ! flag_ci 'worktree'; then
    STAGED_ONLY=true
  fi
  if ! $STAGED_ONLY && { bare_dot || flag_ci 'worktree'; }; then
    block 'git restore of the working tree is blocked — this discards uncommitted changes. Run manually if intentional. `git restore --staged` is allowed.'
  fi
fi

# ── stash drop/clear: throws away shelved work ──────────────────────────────
if sub 'stash' && printf '%s' "$CMD" | grep -qiE 'stash[[:space:]]+(drop|clear)([[:space:]]|$)'; then
  block 'git stash drop/clear is blocked — stashed work cannot be recovered afterwards. Run manually if intentional.'
fi

# ── reflog expire: removes the recovery path for everything above ───────────
if sub 'reflog' && printf '%s' "$CMD" | grep -qiE 'reflog[[:space:]]+(expire|delete)([[:space:]]|$)'; then
  block 'git reflog expire/delete is blocked — the reflog is how mistakes get undone. Run manually if intentional.'
fi

# ── update-ref -d: branch deletion by another name ──────────────────────────
if sub 'update-ref' && flag_cs '[[:space:]]-d([[:space:]]|$)'; then
  block 'git update-ref -d is blocked — this deletes a ref outright. Run manually if intentional.'
fi

exit 0
