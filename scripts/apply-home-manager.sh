#!/bin/sh
# Home Manager switch (non-Windows).
# Task: `mise run apply-home-manager`.
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; skipping Home Manager switch."; exit 0 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Applying Home Manager configuration..."
# Substituters are declared in config/nix-binary-caches.toml and rendered into
# the user nix.conf by Home Manager itself. On the very first switch (and on
# any switch that adds a new cache) the current nix.conf does not yet contain
# them, so inject them via NIX_CONFIG so the switch bootstraps its own caches.
export NIX_CONFIG="$(python3 - "$REPO_ROOT/config/nix-binary-caches.toml" <<'PY'
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit("apply-home-manager requires Python 3.11+ (tomllib)")
with open(sys.argv[1], "rb") as f:
    subs = tomllib.load(f)["nix_substituters"]
print("extra-substituters = " + " ".join(s["url"] for s in subs))
print("extra-trusted-public-keys = " + " ".join(s["key"] for s in subs))
PY
)"

# Use the generic 'default' configuration
nix --extra-experimental-features "flakes nix-command" run home-manager/master -- switch --flake "$HOME/.config/home-manager#default"
