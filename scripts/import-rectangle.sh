#!/bin/sh
# Import Rectangle settings via defaults (macOS only).
# Task: `mise run import-rectangle` (sources: templates/macos/rectangle.plist).
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Not macOS; skipping Rectangle import."
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tmpfile=$(mktemp -t rectangle.plist.XXXXXX)
cleanup() { rm -f "$tmpfile"; }
trap cleanup EXIT INT HUP TERM

cp "$REPO_ROOT/templates/macos/rectangle.plist" "$tmpfile"

# Validate the plist (must be XML1 or binary)
/usr/bin/plutil -lint "$tmpfile" 1>/dev/null

# Import into the Rectangle domain (writes to ~/Library/Preferences)
/usr/bin/defaults import com.knollsoft.Rectangle "$tmpfile"

echo "Imported com.knollsoft.Rectangle settings via defaults import."
