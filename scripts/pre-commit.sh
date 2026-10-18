#!/bin/sh
set -eu

exec pre-commit hook-impl --config .pre-commit-config.yaml \
    --hook-type pre-commit --hook-dir "$(git rev-parse --git-common-dir)/hooks" -- "$@"
