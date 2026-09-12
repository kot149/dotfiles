#!/usr/bin/env pwsh
# Managed Codex settings -> ~/.codex/config.toml (create or merge).
# Task: `mise run apply-codex-config` (sources: templates/codex/config.toml).
$ErrorActionPreference = "Stop"

Write-Host "Updating Codex config..."

$repoRoot = Split-Path -Parent $PSScriptRoot
$configFile = "$HOME/.codex/config.toml"
$specFile = Join-Path $repoRoot "templates/codex/config.toml"
$mergeScript = Join-Path $repoRoot "scripts/merge-codex-config.py"
$outputFile = [System.IO.Path]::GetTempFileName()

try {
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($configFile)) | Out-Null

  if (-not (Test-Path -LiteralPath $configFile)) {
    Copy-Item -LiteralPath $specFile -Destination $configFile
    Write-Host "Created $configFile"
    Write-Host "Done."
    exit 0
  }

  uv run --script $mergeScript $specFile $configFile $outputFile

  Move-Item -LiteralPath $outputFile -Destination $configFile -Force
  Write-Host "Merged managed settings into $configFile"

  Write-Host "Done."
}
finally {
  Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
}
