#!/usr/bin/env pwsh
# Task: `mise run setup`.
$ErrorActionPreference = "Stop"
uv run --script (Join-Path $PSScriptRoot "setup.py")
exit $LASTEXITCODE
