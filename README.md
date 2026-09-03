# Claude Code Guardrails

Safety hooks for [Claude Code](https://claude.com/claude-code). Blocks destructive
shell commands, credential leaks, and unreviewed external MCP calls — in any
project, on macOS, Linux, or Windows.

Copy one file into your project and every Claude Code session in it is guarded.

## What it blocks

| Check | Trigger | Blocks |
|---|---|---|
| `check-rm-rf.sh` | Bash, PowerShell | `rm -rf` and flag variants; `Remove-Item -Recurse -Force` and short forms; `rmdir /S /Q` |
| `check-dangerous-git.sh` | Bash, PowerShell | `git push`, `reset --hard`, `branch -D`, `clean -f`, `checkout -- .` |
| `check-production-guard.sh` | Bash, PowerShell | `DROP TABLE`, `TRUNCATE`, `DELETE`/`UPDATE` without `WHERE` |
| `check-macos-destructive.sh` | Bash | `diskutil eraseDisk`/`eraseVolume`/`zeroDisk`/`secureErase`, `srm -r`, `launchctl bootout system/`, bare `defaults delete` |
| `check-homebrew.sh` | Bash | `brew uninstall --force`, `brew rm --force`, `brew cleanup --prune=all` |
| `check-sensitive-files.sh` | Write, Edit | Writes to `.env`, `*.pem`, `*.key`, `*.p12`, `credentials.json`, SSH keys |
| `check-secrets-write.sh` | Write, Edit | Credential literals in source (passwords, API keys, private keys, bearer tokens, AWS keys) |
| `check-no-hardcoded-paths.sh` | Write, Edit | Machine-specific absolute paths in shared `.claude/` assets |
| `check-mcp-guardrail.sh` | `mcp__*` | Shows the outbound payload for external MCP calls before you consent |
| `git-hooks/pre-push` | `git push` (any caller) | Pushes landing on `main`/`master` — including a bare `git push` whose upstream is `main` |

A blocking check exits `2` and returns a reason, so Claude sees why it was stopped
and can correct course. **Guardrails restrain the agent, not you** — every blocked
command can still be run manually.

## Git-level guard: pushes to `main`

The checks above restrain Claude. This one restrains the `git` client itself — it
catches a push to a protected branch no matter who or what runs it.

```bash
bash git-hooks/install.sh          # current repo
bash git-hooks/install.sh ../app   # another repo
powershell git-hooks/install.ps1   # Windows
```

It inspects the `<remote-ref>` git reports for each pushed ref, which git resolves
*after* refspecs, `HEAD` and upstream tracking are expanded — so one check covers
`git push origin main`, `git push origin HEAD:main`, `git push --delete origin
main`, and a bare `git push` from a branch whose upstream is `main`. Tags and
non-protected branches pass through untouched.

An existing `pre-push` hook is renamed to `pre-push.local` and still runs, after
the guard. If the repo sets `core.hooksPath`, the installer follows it there —
otherwise the hook would be a silent no-op.

This is a local safety net, not access control: `git push --no-verify` bypasses it
and other clones do not have it. Pair it with a server-side branch protection rule
requiring a pull request.

## Install

### 1. Copy the bootstrap script

Copy `run-hooks.sh` into your project at `.claude/hooks/run-hooks.sh` and commit it.
On Windows, copy `run-hooks.ps1` alongside it.

That is the only file your project needs to vendor. The rest of the library is
resolved (and cached) automatically on first use — see
[Resolution order](#resolution-order).

### 2. Wire it into `.claude/settings.json`

**macOS / Linux**

```json
{
  "hooks": {
    "PreToolUse": [{ "type": "command", "command": "bash .claude/hooks/run-hooks.sh pre" }],
    "PostToolUse": [{ "type": "command", "command": "bash .claude/hooks/run-hooks.sh post" }]
  }
}
```

**Windows**

```json
{
  "hooks": {
    "PreToolUse": [{ "type": "command", "command": "powershell .claude/hooks/run-hooks.ps1 pre" }],
    "PostToolUse": [{ "type": "command", "command": "powershell .claude/hooks/run-hooks.ps1 post" }]
  }
}
```

### 3. Verify

Start a Claude Code session and ask it to run `rm -rf /tmp/example`. It should be
blocked with a `[guardrail]` reason.

## Requirements

- **`bash` in `PATH`.** All check logic lives in `.sh` files — a single source of
  truth across platforms. On Windows, install
  [Git for Windows](https://git-scm.com/download/win) (includes Git Bash) or enable
  WSL. `run-hooks.ps1` is a thin launcher that delegates to bash.
- **Node.js in `PATH`,** used to parse the hook JSON payload.

## Resolution order

`run-hooks.sh` looks for the hook library in four places, in order:

1. `$CLAUDE_GUARDRAILS_HOME` — an explicit local checkout
2. A sibling checkout: `<project>/../guardrails` or `<project>/../claude-guardrails`
3. The per-user cache (`~/.claude/guardrails`), refreshed once per TTL window
4. Auto-clone from `$CLAUDE_GUARDRAILS_REPO` into that cache

If all four fail it **exits 0 (fails open)** so Claude Code is never blocked by a
broken guardrail install — it prints a warning instead.

### Configuration

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_GUARDRAILS_REPO` | `https://github.com/alvintayzhenwei/guardrails.git` | Clone source. **Forked this repo? Point this at your own fork,** or your machines will keep pulling from upstream. |
| `CLAUDE_GUARDRAILS_HOME` | *(unset)* | Absolute path to a local checkout. Highest priority — ideal for developing the guardrails themselves. |
| `CLAUDE_GUARDRAILS_CACHE` | `~/.claude/guardrails` | Where the auto-clone lives. |
| `CLAUDE_GUARDRAILS_TTL` | `1440` | Cache refresh interval, in minutes. |
| `PROD_HOST_PATTERN` | *(unset)* | Regex; when set, `check-production-guard.sh` also blocks commands mentioning a matching host. |
| `GUARDRAILS_PROTECTED_BRANCHES` | `main master` | Space-separated, exact-match branch names the `pre-push` guard refuses. |
| `GUARDRAILS_ALLOW_PUSH_PROTECTED` | *(unset)* | Set to `1` for one deliberate push to a protected branch: `GUARDRAILS_ALLOW_PUSH_PROTECTED=1 git push`. |

## Per-project opt-out

Create `.claude/hooks-skip.json` in your project root and name the checks to skip:

```json
{ "skip": ["check-production-guard", "check-no-hardcoded-paths"] }
```

## MCP classification registry

`check-mcp-guardrail.sh` and the auto-classifier (`mcp-classify.js`) both read
`.claude/hooks/mcp-registry.json` **inside your project**. This file is not created
automatically — create it once per project by copying the starter:

```bash
mkdir -p .claude/hooks
cp examples/mcp-registry.json .claude/hooks/mcp-registry.json
```

Without it, `post-tool-use.sh` skips auto-classification entirely and *every*
`mcp__*` tool is treated as external, so every MCP call raises the consent banner —
including purely local ones.

| Field | Purpose |
|---|---|
| `local` | Prefix → `{name, reason}` for MCPs that run as local processes (no consent banner) |
| `external` | Prefix → `{name, reason}` for MCPs that call out to a network service (banner shown) |
| `local_indicators` | Name substrings that auto-classify as **local** |
| `external_indicators` | Name substrings that auto-classify as **external** (takes priority over `local_indicators`) |

Once the file exists, `post-tool-use.sh` runs `mcp-classify.js` after every
`Write`/`Edit`. It scans your settings files for new `mcpServers` and
`enabledPlugins`, classifies each by name match, transport type, or URL, and writes
the result back. Unrecognised MCPs default to **external** — the safe direction.

To reclassify, move a prefix between `local` and `external`; the guardrail re-reads
the file on the next tool call.

## Running the tests

```bash
bash run-tests.sh      # full suite — all checks, all platforms
pwsh run-tests.ps1     # Windows launcher smoke test
```

Exit `0` means every case passed.

## Repo layout

```
guardrails/
├── run-hooks.sh       ← copy into your project's .claude/hooks/
├── run-hooks.ps1      ← copy alongside it on Windows
├── pre-tool-use.sh    ← dispatches PreToolUse checks
├── post-tool-use.sh   ← dispatches PostToolUse checks (MCP auto-classify)
├── mcp-classify.js    ← MCP classification engine
├── run-tests.sh       ← bash test suite
├── run-tests.ps1      ← PowerShell smoke test
├── checks/            ← individual guard scripts
├── git-hooks/         ← git pre-push guard + installer
├── examples/          ← starter mcp-registry.json
└── docs/design/       ← architecture notes
```

## Updating

Push to `main`. Machines using the per-user cache pick up changes on the next
Claude Code session after the TTL expires (24h by default).

## License

MIT — see [LICENSE](LICENSE).
