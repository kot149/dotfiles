#!/usr/bin/env pwsh
# Adopt pre-existing dotfiles into mise management without data loss.
# On apply failure, moved-aside paths are restored before exiting non-zero.
# PowerShell port of scripts/migrate-dotfiles.py. Task: `mise run migrate-from-chezmoi`.
$ErrorActionPreference = "Stop"

uv run --script (Join-Path $PSScriptRoot "setup.py") --migrate
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$statusJson = mise bootstrap dotfiles status -J
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$pending = $statusJson | ConvertFrom-Json |
  Select-Object -ExpandProperty files |
  Where-Object { $_.state -ne "applied" }

if (-not $pending) {
  Write-Host "everything already applied; nothing to migrate."
  exit 0
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $HOME ".local/share/mise-backup/$stamp"
$backups = @{}

try {
  foreach ($entry in $pending) {
    $target = $entry.target
    $tpath = if ($target.StartsWith("~/")) { Join-Path $HOME $target.Substring(2) } else { $target }
    if (Test-Path -LiteralPath $tpath) {
      $rel = [System.IO.Path]::GetRelativePath($HOME, $tpath)
      $bpath = Join-Path $backupRoot $rel
      New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($bpath)) | Out-Null
      Move-Item -LiteralPath $tpath -Destination $bpath -Force
      $backups[$target] = $bpath
      Write-Host "backup: $target -> $bpath"
    }
  }

  mise bootstrap dotfiles apply @($pending | ForEach-Object { $_.target })
  if ($LASTEXITCODE -ne 0) {
    throw "dotfiles apply exited with $LASTEXITCODE"
  }
} catch {
  Write-Host "migration failed ($_); restoring backups from $backupRoot"
  foreach ($target in $backups.Keys) {
    $tpath = if ($target.StartsWith("~/")) { Join-Path $HOME $target.Substring(2) } else { $target }
    $bpath = $backups[$target]
    try {
      if (Test-Path -LiteralPath $tpath) {
        Remove-Item -LiteralPath $tpath -Recurse -Force
      }
      $parent = [System.IO.Path]::GetDirectoryName($tpath)
      if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
      }
      Move-Item -LiteralPath $bpath -Destination $tpath -Force
      Write-Host "restored: $bpath -> $target"
    } catch {
      Write-Warning "cannot restore $target from $bpath`: $_"
    }
  }
  Write-Error "apply failed; originals restored where possible"
  exit 1
}

$kept = @()
foreach ($target in $backups.Keys) {
  $tpath = if ($target.StartsWith("~/")) { Join-Path $HOME $target.Substring(2) } else { $target }
  $bpath = $backups[$target]
  try {
    $old = [System.IO.File]::ReadAllBytes($bpath)
    $new = [System.IO.File]::ReadAllBytes($tpath)
    $same = ($old.Length -eq $new.Length) -and
      ((Compare-Object $old $new -SyncWindow 0).Length -eq 0)
    if ($same) {
      Remove-Item -LiteralPath $bpath -Force
    } else {
      $kept += "$target`: $bpath"
    }
  } catch {
    $kept += "$target`: $bpath"
  }
}

if ($kept.Count -gt 0) {
  Write-Host "review differing backups (kept):"
  $kept | ForEach-Object { Write-Host "  $_" }
} else {
  Write-Host "no differing backups; migration is clean."
}
