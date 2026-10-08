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
case "$TAILSCALED" in
    /nix/store/*) ;;
    *)
        [ "$(stat -f %u "$TAILSCALED")" = 0 ] || {
            echo "refusing to install a user-owned tailscaled into a root LaunchDaemon: $TAILSCALED" >&2
            exit 1
        }
        ;;
esac

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

STATUS=$(tailscale status --json 2>/dev/null || true)
if command -v jq >/dev/null 2>&1; then
    STATE=$(printf '%s' "$STATUS" | jq -r '.BackendState // empty' 2>/dev/null || true)
else
    STATE=$(printf '%s' "$STATUS" | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -n 1)
fi

# tailscale up fails when other preferences differ from the defaults, so it is
# only used for the first login; tailscale set changes just the named ones.
if [ "$STATE" = NeedsLogin ]; then
    tailscale up --ssh --accept-routes
else
    tailscale set --ssh --accept-routes
fi
