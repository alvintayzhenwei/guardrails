#!/usr/bin/env pwsh
# Thin launcher — installs the git pre-push guard on Windows via bash.
# Usage: install.ps1 [<repo-path>]

$target = if ($args[0]) { $args[0] } else { (Get-Location).Path }
& bash "$PSScriptRoot/install.sh" $target
