#!/bin/sh
# tailscaled LaunchDaemon install/teardown (macOS only).
# Task: `mise run apply-tailscaled-launchd`.
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping tailscaled launchd configuration."
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
LABEL=com.tailscale.tailscaled

if ! command -v tailscaled >/dev/null 2>&1; then
    if [ -e "$PLIST" ]; then
        echo "tailscale not installed; tearing down launchd configuration"
        sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
        sudo rm -f "$PLIST"
    fi
    exit 0
fi

# Reinstall when the resolved binary moves (e.g. a Home Manager update points
# tailscaled at a new Nix store path); otherwise the plist keeps referencing a
# path that may vanish on the next GC. Replaces the old checksum trigger that
# embedded the resolved path.
TAILSCALED="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v tailscaled)")"
TAILSCALED_DIR="${TAILSCALED%/*}"
if [ -x "$TAILSCALED_DIR/.tailscaled-wrapped" ]; then
    TAILSCALED="$TAILSCALED_DIR/.tailscaled-wrapped"
fi
INSTALLED="$(python3 - "$PLIST" <<'PY' 2>/dev/null || true
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        print(plistlib.load(f)["ProgramArguments"][0])
except Exception:
    pass
PY
)"
if [ "$INSTALLED" = "$TAILSCALED" ] && [ "$PLIST" -nt "$REPO_ROOT/scripts/macos-launchd/tailscaled.sh" ] && [ "$PLIST" -nt "$REPO_ROOT/scripts/apply-tailscaled-launchd.sh" ]; then
    echo "tailscaled launchd configuration is current ($TAILSCALED)."
    exit 0
fi

sh "$REPO_ROOT/scripts/macos-launchd/tailscaled.sh"
