#!/bin/sh
# Managed VSCode/Cursor settings -> Code + Cursor settings.json (merge).
# Task: `mise run apply-vscode-settings` (sources: templates/vscode/settings.json).
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; use apply-vscode-settings.ps1 instead."; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Updating VSCode settings..."

case "$(uname -s)" in
  Darwin)
    os_name="darwin"
    code_target="$HOME/Library/Application Support/Code/User/settings.json"
    cursor_target="$HOME/Library/Application Support/Cursor/User/settings.json"
    ;;
  *)
    os_name="linux"
    code_target="$HOME/.config/Code/User/settings.json"
    cursor_target="$HOME/.config/Cursor/User/settings.json"
    ;;
esac

spec_file="$REPO_ROOT/templates/vscode/settings.json"
merge_script="$REPO_ROOT/scripts/merge-vscode-settings.py"

mkdir -p "$(dirname "$code_target")" "$(dirname "$cursor_target")"

uv run --script "$merge_script" "$spec_file" "$os_name" "$code_target" "$cursor_target"

echo "Done."
