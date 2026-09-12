#!/bin/sh
# Managed VSCode/Cursor keybindings -> Code + Cursor keybindings.json (merge).
# Task: `mise run apply-vscode-keybindings` (sources: templates/vscode/keybindings.json).
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; use apply-vscode-keybindings.ps1 instead."; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Updating VSCode keybindings..."

case "$(uname -s)" in
  Darwin)
    os_name="darwin"
    code_target="$HOME/Library/Application Support/Code/User/keybindings.json"
    cursor_target="$HOME/Library/Application Support/Cursor/User/keybindings.json"
    ;;
  *)
    os_name="linux"
    code_target="$HOME/.config/Code/User/keybindings.json"
    cursor_target="$HOME/.config/Cursor/User/keybindings.json"
    ;;
esac

spec_file="$REPO_ROOT/templates/vscode/keybindings.json"
merge_script="$REPO_ROOT/scripts/merge-vscode-keybindings.py"

mkdir -p "$(dirname "$code_target")" "$(dirname "$cursor_target")"

uv run --script "$merge_script" "$spec_file" "$os_name" "$code_target" "$cursor_target"

echo "Done."
