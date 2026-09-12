#!/usr/bin/env pwsh
# Managed VSCode/Cursor settings -> Code + Cursor settings.json (merge).
# Task: `mise run apply-vscode-settings` (sources: templates/vscode/settings.json).
$ErrorActionPreference = "Stop"

Write-Host "Updating VSCode settings..."

$repoRoot = Split-Path -Parent $PSScriptRoot
$specFile = Join-Path $repoRoot "templates/vscode/settings.json"
$mergeScript = Join-Path $repoRoot "scripts/merge-vscode-settings.py"
$codeTarget = "$HOME/AppData/Roaming/Code/User/settings.json"
$cursorTarget = "$HOME/AppData/Roaming/Cursor/User/settings.json"

try {
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($codeTarget)) | Out-Null
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($cursorTarget)) | Out-Null

  uv run --script $mergeScript $specFile "windows" $codeTarget $cursorTarget

  Write-Host "Done."
}
finally {
}
