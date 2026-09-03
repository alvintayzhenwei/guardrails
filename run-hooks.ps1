#!/usr/bin/env pwsh
# Thin launcher for Claude Code guardrails on Windows.
# Routes PowerShell hook calls to bash run-hooks.sh (single source of truth).
# Usage: run-hooks.ps1 [pre|post]

$type = if ($args[0]) { $args[0] } else { "pre" }
& bash "$PSScriptRoot/run-hooks.sh" $type
