#!/bin/sh
# Task: `mise run setup`.
set -eu
exec uv run --script "$(dirname "$0")/setup.py"
