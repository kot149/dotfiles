#!/usr/bin/env pwsh
# Managed VSCode/Cursor keybindings -> Code + Cursor keybindings.json (merge).
# Task: `mise run apply-vscode-keybindings` (sources: templates/vscode/keybindings.json).
$ErrorActionPreference = "Stop"

Write-Host "Updating VSCode keybindings..."

$repoRoot = Split-Path -Parent $PSScriptRoot
$specFile = Join-Path $repoRoot "templates/vscode/keybindings.json"
$mergeScript = Join-Path $repoRoot "scripts/merge-vscode-keybindings.py"
$codeTarget = "$HOME/AppData/Roaming/Code/User/keybindings.json"
$cursorTarget = "$HOME/AppData/Roaming/Cursor/User/keybindings.json"

try {
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($codeTarget)) | Out-Null
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($cursorTarget)) | Out-Null

  uv run --script $mergeScript $specFile "windows" $codeTarget $cursorTarget

  Write-Host "Done."
}
finally {
}
