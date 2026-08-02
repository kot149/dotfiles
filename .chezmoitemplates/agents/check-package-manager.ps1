#!/usr/bin/env pwsh
# Warn when using a package manager different from the one detected in the project.
# Block by default; set FORCE_PM=1 to allow.

$ErrorActionPreference = "Stop"

function Get-UsedPackageManager {
    param([string]$Command)

    foreach ($segment in [regex]::Split($Command, '&&|\|\||[;|]|\r?\n')) {
        $words = @($segment.Trim() -split '\s+' | Where-Object { $_ -ne "" })
        if ($words.Count -eq 0) { continue }

        # Skip leading VAR=val assignments
        $idx = 0
        while ($idx -lt $words.Count -and $words[$idx] -match '^[A-Za-z_][A-Za-z0-9_]*=') { $idx++ }
        if ($idx -ge $words.Count) { continue }

        $bin = ($words[$idx] -split '[\\/]')[-1] -replace '\.(exe|cmd|bat|ps1)$', ''
        $next = if ($idx + 1 -lt $words.Count) { $words[$idx + 1] } else { "" }

        switch -Regex ($bin) {
            '^(npm|npx)$'     { return "npm" }
            '^yarn$'          { return "yarn" }
            '^(pnpm|pnpx)$'   { return "pnpm" }
            '^pip3?(\.\d+)?$' { return "pip" }
            '^poetry$'        { return "poetry" }
            '^pipenv$'        { return "pipenv" }
            '^pdm$'           { return "pdm" }
            '^conda$'         { return "conda" }
            '^(bun|bunx)$' {
                if ($bin -eq "bunx" -or $next -in @("install", "add", "remove", "update", "pm", "x")) { return "bun" }
            }
            '^(uv|uvx)$' {
                if ($bin -eq "uvx" -or $next -in @("add", "remove", "sync", "pip", "lock")) { return "uv" }
            }
        }
    }

    return ""
}

function Get-ProjectPackageManager {
    param([string]$Directory, [string]$Used)

    # Only look for lock files in the same language family as the used PM,
    # otherwise a JS lock file in a parent dir can mask a Python project (or vice versa).
    $lockFiles = switch -Regex ($Used) {
        '^(npm|yarn|pnpm|bun)$' {
            @(@("yarn.lock", "yarn"), @("pnpm-lock.yaml", "pnpm"), @("bun.lockb", "bun"), @("bun.lock", "bun"), @("package-lock.json", "npm"))
            break
        }
        '^(pip|poetry|pipenv|pdm|uv|conda)$' {
            @(@("uv.lock", "uv"), @("poetry.lock", "poetry"), @("Pipfile.lock", "pipenv"), @("pdm.lock", "pdm"))
            break
        }
        default { @() }
    }
    if ($lockFiles.Count -eq 0) { return "" }

    $dir = $Directory
    while ($true) {
        foreach ($entry in $lockFiles) {
            if (Test-Path -LiteralPath (Join-Path $dir $entry[0]) -PathType Leaf) { return $entry[1] }
        }

        # Stop at git root to avoid leaking into parent repos
        if (Test-Path -LiteralPath (Join-Path $dir ".git") -PathType Container) { break }

        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }

    return ""
}

$input_json = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($input_json)) { exit 0 }

try { $payload = $input_json | ConvertFrom-Json } catch { exit 0 }

$command = [string]$payload.tool_input.command
if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

$cwd = [string]$payload.cwd
if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = (Get-Location).Path }

$usedPm = Get-UsedPackageManager -Command $command
if ($usedPm -eq "") { exit 0 }

$projectPm = Get-ProjectPackageManager -Directory $cwd -Used $usedPm
if ($projectPm -eq "" -or $projectPm -eq $usedPm) { exit 0 }

# Allow if FORCE_PM=1 is set in env or prepended to the command
if ($env:FORCE_PM -eq "1" -or $command -match 'FORCE_PM=1') {
    [Console]::Error.WriteLine("[PM Warning] Using $usedPm but project uses $projectPm (FORCE_PM=1 set, allowing)")
    exit 0
}

$reason = @"
[Package Manager Mismatch]

  Detected PM: $usedPm
  Project PM:  $projectPm  (detected from lock file)
  Project:     $cwd

Please use $projectPm instead.
To force execution, set FORCE_PM=1:

  FORCE_PM=1 $command
"@

[Console]::Error.WriteLine($reason)

# Deny via hook JSON output; a non-zero exit status is not a block signal in Codex.
$decision = @{
    hookSpecificOutput = @{
        hookEventName            = "PreToolUse"
        permissionDecision       = "deny"
        permissionDecisionReason = $reason
    }
}
[Console]::Out.WriteLine(($decision | ConvertTo-Json -Depth 5 -Compress))
exit 0
