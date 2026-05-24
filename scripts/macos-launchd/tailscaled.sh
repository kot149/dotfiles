sudo tee /Library/LaunchDaemons/com.tailscale.tailscaled.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tailscale.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which tailscaled)</string>
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

sudo launchctl load -w /Library/LaunchDaemons/com.tailscale.tailscaled.plist

tailscale up --ssh --accept-routes
