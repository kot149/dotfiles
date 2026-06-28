#!/bin/sh
set -eu

PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
LABEL=com.tailscale.tailscaled
# Resolve to the actual /nix/store path. ~/.nix-profile lives under the
# FileVault-encrypted user home, which root's launchd cannot read at boot
# (`No such file or directory` -> service ends up in the penalty box).
TAILSCALED=$(readlink -f "$(which tailscaled)")

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
