#!/bin/sh
# Managed Antigravity permissions -> ~/.gemini/antigravity-cli/settings.json.
# Only the .permissions subtree is managed; the rest of the file is untouched.
# Task: `mise run apply-antigravity-config` (sources: generated/antigravity-settings.json).
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; use apply-antigravity-config.ps1 instead."; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Updating Antigravity CLI config..."

config_file="$HOME/.gemini/antigravity-cli/settings.json"
spec_file="$REPO_ROOT/generated/antigravity-settings.json"
output_file="$(mktemp)"

cleanup() {
  rm -f "$output_file"
}
trap cleanup EXIT

mkdir -p "$(dirname "$config_file")"

if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
  cp "$spec_file" "$config_file"
  echo "Created $config_file"
  echo "Done."
  exit 0
fi

jq --slurpfile spec "$spec_file" '.permissions = $spec[0].permissions' "$config_file" >"$output_file"
mv "$output_file" "$config_file"
echo "Merged managed permissions into $config_file"

echo "Done."
