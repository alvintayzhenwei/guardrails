# Claude Code Guardrails

[![release](https://img.shields.io/github/v/tag/alvintayzhenwei/guardrails?label=release&sort=semver&color=fe7d37)](https://github.com/alvintayzhenwei/guardrails/tags)
[![CI](https://github.com/alvintayzhenwei/guardrails/actions/workflows/ci.yml/badge.svg)](https://github.com/alvintayzhenwei/guardrails/actions/workflows/ci.yml)
[![ShellCheck](https://github.com/alvintayzhenwei/guardrails/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/alvintayzhenwei/guardrails/actions/workflows/shellcheck.yml)
[![Audit](https://github.com/alvintayzhenwei/guardrails/actions/workflows/audit.yml/badge.svg)](https://github.com/alvintayzhenwei/guardrails/actions/workflows/audit.yml)
[![CodeQL](https://github.com/alvintayzhenwei/guardrails/actions/workflows/codeql.yml/badge.svg)](https://github.com/alvintayzhenwei/guardrails/actions/workflows/codeql.yml)
[![bypass tests](https://img.shields.io/badge/bypass%20tests-149%20passing-brightgreen)](run-vuln-tests.sh)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Safety hooks for [Claude Code](https://claude.com/claude-code). Designed to
refuse destructive shell commands, credential writes, and unreviewed external
MCP calls — in any project, on macOS, Linux, or Windows.

Copy one file into your project and these checks run on every Claude Code tool
call in it.

> [!IMPORTANT]
> **This is one layer of defence, not a solution, and it is not foolproof.**
> It is pattern matching over the text of a tool call — useful against an agent
> making a mistake, and no substitute for backups, server-side branch
> protection, or reviewing what an agent does. It will not catch everything and
> is not intended to. If it cannot load, it **fails open and your session runs
> unprotected** — so the absence of a block never means a command was checked
> and approved.
>
> Provided "as is", with no warranty and no liability, under the
> [MIT License](LICENSE). Read [DISCLAIMER.md](DISCLAIMER.md) before relying on
> it for anything you cannot afford to lose.

**Don't trust it — check it.** This tool asks for a hook on every tool call in
your project, so it should have to earn that. `bash run-vuln-tests.sh` runs 149
offline evasion attempts against the guards and tells you which ones got
through. [SECURITY.md](SECURITY.md) states plainly what the guards do *not*
defend against.

## What it is designed to refuse

The patterns below are what the checks look for. The list is **not exhaustive of
destructive commands** — it is exhaustive of what these checks recognise. Any
spelling not listed, and anything the shell only assembles at run time, passes
through.

| Check | Trigger | Patterns it refuses |
|---|---|---|
| `check-rm-rf.sh` | Bash, PowerShell | `rm -rf` in the spellings listed here — combined, separate, uppercase `-R`, GNU `--recursive --force`; `find -delete`; `Remove-Item -Recurse -Force` and its `ri`/`rd`/`rmdir`/`del`/`erase` aliases; `rmdir /S /Q` |
| `check-dangerous-git.sh` | Bash, PowerShell | `git push`, `reset --hard`, `branch -D`, `clean -f`, `checkout .`, `restore`, `stash drop`/`clear`, `reflog expire`, `update-ref -d` — matched through git's global options, so `git -c … push` is caught too |
| `check-production-guard.sh` | Bash, PowerShell | `DROP TABLE`/`DATABASE`/`SCHEMA`, `TRUNCATE`, `DELETE`/`UPDATE` without a row-narrowing `WHERE` (a tautological `WHERE 1=1` does not count) |
| `check-macos-destructive.sh` | Bash | `diskutil eraseDisk`/`eraseVolume`/`zeroDisk`/`secureErase`/`apfs deleteContainer`, `srm -r`, `launchctl bootout system/`, bare `defaults delete` |
| `check-homebrew.sh` | Bash | `brew uninstall --force`, `brew rm --force`, `brew cleanup --prune=all` |
| `check-sensitive-files.sh` | any write tool | Writes to `.env`, `.envrc`, `*.pem`, `*.key`, `*.p12`, `*.ppk`, `credentials`, `.netrc`, `.npmrc`, `.git-credentials`, SSH keys — case-insensitively, since macOS and Windows filesystems are |
| `check-secrets-write.sh` | any write tool | Credential literals in source: password/secret assignments plus AWS, GitHub, Slack, Google, Stripe, GitLab, npm, OpenAI and Anthropic token formats, and private key blocks |
| `check-no-hardcoded-paths.sh` | any write tool | Machine-specific absolute paths in shared `.claude/` assets |
| `check-mcp-guardrail.sh` | `mcp__*` | Shows the outbound payload for external MCP calls before you consent |
| `git-hooks/pre-push` | `git push` (any caller) | Pushes landing on `main`/`master` — including a bare `git push` whose upstream is `main` |

A blocking check exits `2` and returns a reason, so Claude sees why it was stopped
and can correct course. **Guardrails restrain the agent, not you** — every blocked
command can still be run manually.

"Any write tool" is literal: the dispatcher routes `Write`, `Edit`, `MultiEdit`,
`NotebookEdit` and anything else matching `*Edit`/`*Write`, so a newly
introduced file-mutating tool is guarded by default rather than silently
unguarded until someone adds its name.

## Git-level guard: pushes to `main`

The checks above restrain Claude. This one restrains the `git` client itself — it
catches a push to a protected branch whichever caller runs it, unless that caller
skips hooks (see the caveat below).

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
bash run-tests.sh        # 95 assertions  — do the guards fire as documented?
bash run-vuln-tests.sh   # 149 assertions — can the same effect get past them?
pwsh run-tests.ps1       # Windows launcher smoke test
```

Exit `0` means every case passed. Both suites are offline and take seconds.

### The adversarial suite

`run-tests.sh` asks whether each guard fires on its documented pattern.
`run-vuln-tests.sh` asks the harder question: **can the same destructive effect
get past it anyway?** Every case in it is an evasion attempt, grouped by attack
class — flag obfuscation, binary indirection, command chaining, alias
substitution, case tricks, tautological SQL, exemption abuse, and tool-name
evasion.

Cases that expect exit `0` are **documented non-goals**, not gaps waiting to be
fixed: a static text guard cannot resolve a flag the shell will only assemble at
run time. They are pinned in the suite so the boundary is recorded rather than
assumed, and explained in [SECURITY.md](SECURITY.md#threat-model).

Written against the guards as they stood, the suite found 65 successful evasions
and three cases of the opposite problem — guards blocking legitimate commands
(`git branch -d` on a merged branch, `grep "DROP TABLE"`, writing
`.env.example`). All are closed. If you find a 66th,
[SECURITY.md](SECURITY.md#reporting-a-vulnerability) has the reporting path.

## Security

- **What it does and does not defend against:** [SECURITY.md](SECURITY.md) — the
  threat model, and five explicit out-of-scope items including the loader's
  deliberate fail-open behaviour.
- **Reporting a bypass:** privately, via GitHub Security Advisories on this
  repository. Please not a public issue.
- **What runs on every change:** the behaviour suite and the adversarial suite
  on Linux, macOS and Windows (CI); ShellCheck; CodeQL over the JavaScript and
  the workflows themselves; and an audit job that runs `check-secrets-write`
  against this repo's own tree, asserts no guard script touches the network, and
  fails if the bypass-test badge above disagrees with the real assertion count.

## Repo layout

```
guardrails/
├── run-hooks.sh       ← copy into your project's .claude/hooks/
├── run-hooks.ps1      ← copy alongside it on Windows
├── pre-tool-use.sh    ← dispatches PreToolUse checks
├── post-tool-use.sh   ← dispatches PostToolUse checks (MCP auto-classify)
├── mcp-classify.js    ← MCP classification engine
├── run-tests.sh       ← behaviour suite: do the guards fire as documented?
├── run-vuln-tests.sh  ← adversarial suite: can anything get past them?
├── run-tests.ps1      ← PowerShell smoke test
├── SECURITY.md        ← threat model, non-goals, disclosure policy
├── DISCLAIMER.md      ← no warranty, no liability, limits of the approach
├── checks/            ← individual guard scripts
├── git-hooks/         ← git pre-push guard + installer
├── examples/          ← starter mcp-registry.json
├── .github/workflows/ ← CI, ShellCheck, Audit, CodeQL
└── docs/design/       ← architecture notes
```

## Updating

Push to `main`. Machines using the per-user cache pick up changes on the next
Claude Code session after the TTL expires (24h by default).

## Disclaimer

**No warranty. No liability. One layer of defence, not a solution.**

This software is pattern matching over the text of a tool call. It will not
catch every destructive command and is not intended to; it is not a sandbox, an
access-control system, a backup, or a substitute for reviewing what an agent
does. If the library cannot load it **fails open and your session runs with no
protection**, so the absence of a block never means a command was checked and
approved. Green badges and a passing 149-case adversarial suite mean those
recorded cases behaved as recorded — not that no bypass exists.

You remain responsible for your own backups, branch protection, credential
hygiene, and for deciding whether this software suits your environment. The
entire risk of using it is yours.

Full terms: **[DISCLAIMER.md](DISCLAIMER.md)** — please read it before relying
on this for anything you cannot afford to lose.

## License

MIT — see [LICENSE](LICENSE). The MIT text governs your use of this software,
including its warranty disclaimer and limitation of liability:

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND … IN NO EVENT
> SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
> OTHER LIABILITY …

Not affiliated with Anthropic. "Claude" and "Claude Code" are their products.
