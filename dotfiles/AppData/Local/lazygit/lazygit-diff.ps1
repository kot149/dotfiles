#!/usr/bin/env pwsh

$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
[Console]::InputEncoding = $utf8
$OutputEncoding = $utf8
$env:LESSCHARSET = 'utf-8'

$old = $args[1].Replace('\', '/')
$new = $args[4].Replace('\', '/')
$path = $args[0]

$hunk = Get-Command hunk -CommandType Application -ErrorAction Stop
$hunkRoot = Split-Path (Split-Path $hunk.Source)
$hunkMain = Join-Path $hunkRoot 'install/global/node_modules/hunkdiff/dist/npm/main.js'
if (-not (Test-Path -LiteralPath $hunkMain)) {
  throw "hunkdiff entrypoint not found: $hunkMain"
}

$hunkMainUrl = ([System.Uri]$hunkMain).AbsoluteUri
$hunkBootstrap = @"
Object.defineProperty(process.stdout, "isTTY", { value: true });
Object.defineProperty(process.stdout, "columns", { value: Number(process.env.LAZYGIT_COLUMNS) || 120 });
process.argv = ["bun", "hunk", "pager", "--mode", "split"];
await import("$hunkMainUrl");
"@

$env:TERM = 'dumb'
if (-not $env:LAZYGIT_COLUMNS) {
  $env:LAZYGIT_COLUMNS = '120'
}

git -c core.pager=cat diff --no-index --no-ext-diff -- $old $new |
  ForEach-Object { $_.Replace($old, $path).Replace($new, $path) } |
  & bun -e $hunkBootstrap
