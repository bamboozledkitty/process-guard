#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building ProcessGuard..."
swiftc -O -o ProcessGuard Sources/ProcessGuard/main.swift -framework AppKit

# Build the .app bundle structure
mkdir -p ProcessGuard.app/Contents/MacOS
cp ProcessGuard ProcessGuard.app/Contents/MacOS/ProcessGuard

# Write Info.plist if missing
if [ ! -f ProcessGuard.app/Contents/Info.plist ]; then
cat > ProcessGuard.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProcessGuard</string>
    <key>CFBundleIdentifier</key>
    <string>com.keithvaz.processguard</string>
    <key>CFBundleName</key>
    <string>ProcessGuard</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSBackgroundOnly</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST
fi

# Install the app bundle to ~/Applications
APP_DEST="$HOME/Applications/ProcessGuard.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R ProcessGuard.app "$APP_DEST"
echo "Installed to $APP_DEST"

APP_BINARY="$APP_DEST/Contents/MacOS/ProcessGuard"

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
        <string>${APP_BINARY}</string>
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
echo "To start now:  open $APP_DEST"
echo "To auto-start: launchctl load $PLIST"
echo "To stop auto:  launchctl unload $PLIST"
