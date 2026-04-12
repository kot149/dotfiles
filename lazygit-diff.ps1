#!/usr/bin/env pwsh

$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
[Console]::InputEncoding = $utf8
$OutputEncoding = $utf8
$env:LESSCHARSET = 'utf-8'

$old = $args[1].Replace('\', '/')
$new = $args[4].Replace('\', '/')
$path = $args[0]

$deltaArgs = @()
if ($env:LAZYGIT_COLUMNS -and $env:LAZYGIT_COLUMNS.Trim() -ne '') {
  $deltaArgs += "--width=$($env:LAZYGIT_COLUMNS.Trim())"
}

git -c core.pager=cat diff --no-index --no-ext-diff -- $old $new |
  ForEach-Object { $_.Replace($old, $path).Replace($new, $path) } |
  & delta @deltaArgs
