#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building ProcessGuard..."
swiftc -O -o ProcessGuard Sources/ProcessGuard/main.swift -framework AppKit

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
cp ProcessGuard "$INSTALL_DIR/ProcessGuard"
echo "Installed to $INSTALL_DIR/ProcessGuard"

# Create LaunchAgent for auto-start on login
PLIST="$HOME/Library/LaunchAgents/com.keithvaz.processguard.plist"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.keithvaz.processguard</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/ProcessGuard</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

echo "Created LaunchAgent at $PLIST"
echo ""
echo "To start now:  $INSTALL_DIR/ProcessGuard &"
echo "To auto-start: launchctl load $PLIST"
echo "To stop auto:  launchctl unload $PLIST"
