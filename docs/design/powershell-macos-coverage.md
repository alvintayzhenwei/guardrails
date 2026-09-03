# Design: PowerShell & macOS Guardrail Coverage Extension

**Date:** 2026-05-11
**Status:** Approved

## Problem

The current guardrail library is entirely bash-based and only fires when Claude uses the `Bash` tool. Two gaps exist:

1. **PowerShell tool not covered** — Claude Code on Windows exposes a distinct `PowerShell` tool. Commands like `Remove-Item -Recurse -Force` via the PowerShell tool bypass all guardrails.
2. **macOS-specific destructive commands uncovered** — `diskutil eraseDisk`, `srm -rf`, `launchctl bootout`, `brew uninstall --force`, and similar macOS-specific commands are not guarded.

## Goal

Guardrails fire consistently regardless of which shell environment the developer is on (Windows PowerShell, macOS bash/zsh, Linux bash) — with a single maintainable codebase.

## Key Architectural Decision

Hooks in Claude Code are run by the **harness**, not by the intercepted tool. When Claude uses the `PowerShell` tool, the hook command (`bash run-hooks.sh pre`) is still executed by bash. The hook receives the PowerShell command text as `HOOK_COMMAND` in the JSON payload.

This means:
- All check **logic stays in `.sh` files** (single source of truth)
- PowerShell tool calls are routed to the same bash checks, which are extended to recognise PowerShell syntax
- `run-hooks.ps1` is a **3-line thin launcher** only — no parallel logic

## Architecture

### File Changes

```
guardrails/
├── run-hooks.sh              ← shebang fix: /usr/bin/env bash
├── run-hooks.ps1             ← NEW: 3-line launcher → delegates to bash
├── pre-tool-use.sh           ← add PowerShell to Bash case branch
├── post-tool-use.sh          ← unchanged
├── mcp-classify.js           ← unchanged
├── run-tests.sh              ← extended with PS + macOS test cases
├── run-tests.ps1             ← NEW: PS launcher smoke test
└── checks/
    ├── check-rm-rf.sh               ← extended with PowerShell patterns
    ├── check-dangerous-git.sh       ← unchanged (git syntax is the same)
    ├── check-production-guard.sh    ← unchanged (SQL is the same)
    ├── check-macos-destructive.sh   ← NEW
    ├── check-homebrew.sh            ← NEW
    ├── check-sensitive-files.sh     ← unchanged
    ├── check-secrets-write.sh       ← unchanged
    ├── check-no-hardcoded-paths.sh  ← unchanged (/Users/* already matched)
    └── check-mcp-guardrail.sh       ← unchanged
```

### Tool-to-Check Routing

| Claude Code tool | Hook runner | Dispatcher | Checks applied |
|---|---|---|---|
| `Bash` | `run-hooks.sh` | `pre-tool-use.sh` | rm-rf, dangerous-git, production-guard, macos-destructive, homebrew |
| `PowerShell` | `run-hooks.ps1` → bash | `pre-tool-use.sh` | rm-rf (+ PS patterns), dangerous-git, production-guard (macOS/Homebrew checks not applicable) |
| `Write`/`Edit` | either | `pre-tool-use.sh` | sensitive-files, secrets-write, no-hardcoded-paths |
| `mcp__*` | either | `pre-tool-use.sh` | mcp-guardrail |

## Detailed Changes

### 1. `run-hooks.sh` — shebang fix

Change `#!/bin/bash` → `#!/usr/bin/env bash` for clean resolution on macOS with Homebrew bash.

### 2. `run-hooks.ps1` — thin launcher (new)

```powershell
#!/usr/bin/env pwsh
$type = if ($args[0]) { $args[0] } else { "pre" }
& bash "$PSScriptRoot/run-hooks.sh" $type
```

**Requirement:** bash must be in PATH (Git Bash, WSL, or system bash). This is the same requirement as the existing `run-hooks.sh` — no new constraint introduced.

### 3. `pre-tool-use.sh` — dispatcher update

```bash
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
    ...
```

### 4. `check-rm-rf.sh` — PowerShell patterns added

Extended to also block:

| Pattern | Notes |
|---|---|
| `Remove-Item -Recurse -Force` | All flag orderings (6 permutations) |
| `Remove-Item -r -fo` / `-r -f` | Short form flags |
| `ri -Recurse -Force` | `ri` alias for Remove-Item |
| `rmdir /S /Q` | CMD-style invoked from PowerShell |

### 5. `check-macos-destructive.sh` — new

Blocks on `Bash` tool:

| Pattern | Reason |
|---|---|
| `diskutil eraseDisk` | Wipes entire disk |
| `diskutil eraseVolume` | Wipes volume |
| `diskutil zeroDisk` | Secure wipe |
| `diskutil secureErase` | Secure wipe |
| `srm -r` / `srm -rf` | Secure recursive delete |
| `launchctl bootout system/` | Unloads system-level daemons |
| `defaults delete` (end of string or followed only by whitespace) | Global user defaults wipe — targeted `defaults delete com.apple.foo` is allowed |
| `rm -rf /` | Root filesystem wipe |

### 6. `check-homebrew.sh` — new

Blocks on `Bash` tool:

| Pattern | Reason |
|---|---|
| `brew uninstall --force` | Force-removes ignoring deps |
| `brew rm --force` | Alias for uninstall --force |
| `brew cleanup --prune=all` | Deletes all cached versions |

### 7. `run-tests.sh` — extended

New test cases added for:
- PowerShell `Remove-Item` variants (runnable via bash since tests set `HOOK_COMMAND`)
- macOS destructive command blocks and expected allows
- Homebrew guard blocks and expected allows

### 8. `run-tests.ps1` — new smoke test

Verifies that `run-hooks.ps1` correctly delegates to bash and that the PowerShell tool name routes through the dispatcher. This is a launcher test, not a logic test.

## README Updates

- New section: **Platform setup** with per-OS `settings.json` snippets
  - macOS/Linux: `bash .claude/hooks/run-hooks.sh pre`
  - Windows: `powershell .claude/hooks/run-hooks.ps1 pre`
- Updated guardrail table with `check-macos-destructive` and `check-homebrew` rows
- Note that bash must be in PATH on Windows (Git Bash / WSL)

## What Is Not Changing

- All check logic remains in `.sh` files — single source of truth
- No parallel `.ps1` check scripts — avoids dual-maintenance drift
- `post-tool-use.sh` and MCP classification unchanged
- `check-no-hardcoded-paths.sh` already handles `/Users/username/` macOS paths — no change needed

## Testing Strategy

- `run-tests.sh` covers all bash checks including new macOS/PS patterns
- `run-tests.ps1` smoke-tests the PS launcher on Windows
- Both test files can be run in CI on their respective platforms

## Success Criteria

- `Remove-Item -Recurse -Force` via PowerShell tool is blocked
- `diskutil eraseDisk` via Bash tool is blocked on any platform
- `brew uninstall --force` via Bash tool is blocked
- `run-hooks.ps1` works on Windows with Git Bash in PATH
- `run-hooks.sh` shebang resolves cleanly on macOS with Homebrew bash
- All existing tests continue to pass
