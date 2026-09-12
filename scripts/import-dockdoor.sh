#!/bin/sh
# Import DockDoor settings via defaults (macOS only).
# Task: `mise run import-dockdoor` (sources: templates/macos/dockdoor.plist).
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping DockDoor import."
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tmpfile=$(mktemp -t dockdoor.plist.XXXXXX)
cleanup() { rm -f "$tmpfile"; }
trap cleanup EXIT INT HUP TERM

cp "$REPO_ROOT/templates/macos/dockdoor.plist" "$tmpfile"

# Validate the plist (must be XML1 or binary)
/usr/bin/plutil -lint "$tmpfile" 1>/dev/null

# Import into the DockDoor domain (writes to ~/Library/Preferences)
/usr/bin/defaults import com.ethanbills.DockDoor "$tmpfile"

echo "Imported com.ethanbills.DockDoor settings via defaults import."
