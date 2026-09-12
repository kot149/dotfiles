#!/usr/bin/env pwsh
# Managed Antigravity permissions -> ~/.gemini/antigravity-cli/settings.json.
# Only the .permissions subtree is managed; the rest of the file is untouched.
# Task: `mise run apply-antigravity-config` (sources: generated/antigravity-settings.json).
$ErrorActionPreference = "Stop"

Write-Host "Updating Antigravity CLI config..."

$repoRoot = Split-Path -Parent $PSScriptRoot
$configFile = "$HOME/.gemini/antigravity-cli/settings.json"
$specFile = Join-Path $repoRoot "generated/antigravity-settings.json"

try {
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($configFile)) | Out-Null

  $specJson = Get-Content -LiteralPath $specFile -Raw | ConvertFrom-Json

  if (-not (Test-Path -LiteralPath $configFile) -or ((Get-Item -LiteralPath $configFile).Length -eq 0)) {
    Copy-Item -LiteralPath $specFile -Destination $configFile -Force
    Write-Host "Created $configFile"
    Write-Host "Done."
    exit 0
  }

  $configJson = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
  $configJson | Add-Member -NotePropertyName 'permissions' -NotePropertyValue $specJson.permissions -Force
  $configJson | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $configFile -Encoding utf8NoBOM
  Write-Host "Merged managed permissions into $configFile"

  Write-Host "Done."
}
finally {
}
