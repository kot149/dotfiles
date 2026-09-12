#!/bin/sh
# Managed Codex settings -> ~/.codex/config.toml (create or merge).
# Task: `mise run apply-codex-config` (sources: templates/codex/config.toml).
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; use apply-codex-config.ps1 instead."; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Updating Codex config..."

config_file="$HOME/.codex/config.toml"
spec_file="$REPO_ROOT/templates/codex/config.toml"
merge_script="$REPO_ROOT/scripts/merge-codex-config.py"
output_file="$(mktemp)"

cleanup() {
  rm -f "$output_file"
}
trap cleanup EXIT

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ]; then
  cp "$spec_file" "$config_file"
  echo "Created $config_file"
  echo "Done."
  exit 0
fi

uv run --script "$merge_script" "$spec_file" "$config_file" "$output_file"

mv "$output_file" "$config_file"
echo "Merged managed settings into $config_file"

echo "Done."
