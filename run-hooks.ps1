#!/usr/bin/env pwsh
# =============================================================================
# Thin launcher for Claude Code guardrails on Windows.
# Routes PowerShell hook calls to bash run-hooks.sh (single source of truth).
# Usage: run-hooks.ps1 [pre|post]
#
# DISCLAIMER — NO WARRANTY, NO LIABILITY
# These hooks are ONE LAYER OF DEFENCE, NOT A SOLUTION, and are NOT FOOLPROOF.
# They are pattern matching over the text of a tool call: they will not catch
# every destructive command and are not intended to. They are not a sandbox,
# not access control, and NOT A SUBSTITUTE FOR BACKUPS, server-side branch
# protection, or reviewing what an agent does.
#
# The loader FAILS OPEN: if the library cannot be resolved the session continues
# WITH NO PROTECTION AT ALL. The absence of a block therefore NEVER means a
# command was checked and approved.
#
# Provided "as is" under the MIT License, without warranty of any kind and with
# no liability for any claim or damages. The entire risk of use is yours.
# Full terms: https://github.com/alvintayzhenwei/guardrails/blob/main/DISCLAIMER.md
# =============================================================================

$type = if ($args[0]) { $args[0] } else { "pre" }
& bash "$PSScriptRoot/run-hooks.sh" $type
