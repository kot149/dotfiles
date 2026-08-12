#!/bin/sh
set -eu

PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
LABEL=com.tailscale.tailscaled
# Resolve to a root-readable executable. ~/.nix-profile lives under the
# FileVault-encrypted user home, and the Nix entrypoint is a shell wrapper.
TAILSCALED=$(readlink -f "$(command -v tailscaled)")
TAILSCALED_DIR=${TAILSCALED%/*}
if [ -x "$TAILSCALED_DIR/.tailscaled-wrapped" ]; then
    TAILSCALED="$TAILSCALED_DIR/.tailscaled-wrapped"
fi

sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TAILSCALED}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/tailscaled.err.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/tailscaled.out.log</string>
</dict>
</plist>
EOF

sudo launchctl bootout system/"$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"

tailscale up --ssh --accept-routes
