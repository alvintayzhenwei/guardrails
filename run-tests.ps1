#!/usr/bin/env pwsh
# Smoke-test: PowerShell tool routing via bash check scripts.
# Requires bash in PATH (Git Bash or WSL on Windows, native on macOS/Linux).

$ErrorActionPreference = "Stop"

$pass = 0; $fail = 0

function chk($expected, $actual, $desc) {
  if ($actual -eq $expected) {
    Write-Host "  PASS: $desc"; $script:pass++
  } else {
    Write-Host "  FAIL: $desc  (expected exit $expected, got $actual)"; $script:fail++
  }
}

Write-Host ""
Write-Host "=== PowerShell dispatcher smoke test ==="

Push-Location $PSScriptRoot

# Dangerous: Remove-Item -Recurse -Force — should be blocked (exit 2)
& bash -c "HOOK_TOOL_NAME='PowerShell' HOOK_COMMAND='Remove-Item -Recurse -Force C:\tmp\foo' bash checks/check-rm-rf.sh" > $null 2>&1
chk 2 $LASTEXITCODE "PowerShell tool: blocks Remove-Item -Recurse -Force"

# Safe: Get-ChildItem — should be allowed (exit 0)
& bash -c "HOOK_TOOL_NAME='PowerShell' HOOK_COMMAND='Get-ChildItem C:\tmp' bash checks/check-rm-rf.sh" > $null 2>&1
chk 0 $LASTEXITCODE "PowerShell tool: allows Get-ChildItem"

# Dangerous: git push via PowerShell — should be blocked (exit 2)
& bash -c "HOOK_TOOL_NAME='PowerShell' HOOK_COMMAND='git push origin main' bash checks/check-dangerous-git.sh" > $null 2>&1
chk 2 $LASTEXITCODE "PowerShell tool: blocks git push"

# Safe: git status via PowerShell — should be allowed (exit 0)
& bash -c "HOOK_TOOL_NAME='PowerShell' HOOK_COMMAND='git status' bash checks/check-dangerous-git.sh" > $null 2>&1
chk 0 $LASTEXITCODE "PowerShell tool: allows git status"

Pop-Location

Write-Host ""
Write-Host "======================================="
Write-Host "  Results: $pass passed, $fail failed"
Write-Host "======================================="
Write-Host ""

if ($fail -gt 0) { exit 1 } else { exit 0 }
