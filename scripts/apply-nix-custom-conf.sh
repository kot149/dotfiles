#!/bin/sh
# System-wide nix.custom.conf block (non-Windows, daemon installs only).
# Task: `mise run apply-nix-custom-conf`.
set -eu

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "Windows detected; skipping nix.custom.conf."; exit 0 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Substituters requested through the user-level nix.conf are dropped by the Nix
# daemon unless the user is in trusted-users, so the caches have to be declared
# system-wide as well. Determinate Nix owns /etc/nix/nix.conf and pulls user
# settings in from nix.custom.conf.
conf=/etc/nix/nix.custom.conf

# Only meaningful on daemon installs that include nix.custom.conf.
grep -q '!include nix.custom.conf' /etc/nix/nix.conf 2>/dev/null || exit 0

begin='# BEGIN mise managed'
end='# END mise managed'

export USER="${USER:-$(id -un)}"
block="$(python3 - "$REPO_ROOT/config/nix-binary-caches.toml" <<'PY'
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit("apply-nix-custom-conf requires Python 3.11+ (tomllib)")
with open(sys.argv[1], "rb") as f:
    subs = tomllib.load(f)["nix_substituters"]
print("# BEGIN mise managed")
print("trusted-users = root " + __import__("os").environ.get("USER", ""))
print("extra-substituters = " + " ".join(s["url"] for s in subs))
print("extra-trusted-public-keys = " + " ".join(s["key"] for s in subs))
print("# END mise managed")
PY
)"

existing=$(cat "$conf" 2>/dev/null || true)
# Also strip blocks written by the previous chezmoi-based setup one final time.
kept=$(printf '%s\n' "$existing" | awk -v b1="$begin" -v e1="$end" -v b2='# BEGIN chezmoi managed' -v e2='# END chezmoi managed' '$0==b1||$0==b2{s=1} !s; $0==e1||$0==e2{s=0}')
if [ -n "$kept" ]; then
	desired="$kept
$block"
else
	desired="$block"
fi

if [ "$existing" = "$desired" ]; then
	exit 0
fi

echo "Updating $conf (sudo required)..."
printf '%s\n' "$desired" | sudo tee "$conf" >/dev/null

echo "Restarting the Nix daemon..."
if [ "$(uname -s)" = "Darwin" ]; then
  for label in systems.determinate.nix-daemon org.nixos.nix-daemon; do
    if sudo launchctl print "system/$label" >/dev/null 2>&1; then
      sudo launchctl kickstart -k "system/$label"
      break
    fi
  done
else
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl restart nix-daemon
  fi
fi
