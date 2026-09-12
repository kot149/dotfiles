#!/bin/sh
# nix-darwin switch (macOS only).
# Task: `mise run apply-nix-darwin`.
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping nix-darwin switch."
  exit 0
fi

NIX_DARWIN_DIR="$HOME/.config/nix-darwin"

cd "$NIX_DARWIN_DIR"

echo "Applying nix-darwin configuration..."
nix flake update
sudo -H nix --extra-experimental-features 'nix-command flakes' run github:LnL7/nix-darwin#darwin-rebuild -- switch --flake .#"$(hostname -s)"

echo "nix-darwin configuration applied successfully"
