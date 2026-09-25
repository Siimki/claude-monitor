#!/bin/bash
# Builds ClaudeMonitor in release mode and assembles a double-clickable
# .app bundle (menu-bar agent, no Dock icon). Output: ./ClaudeMonitor.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building release…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/ClaudeMonitor"
BRIDGE="$BIN_DIR/ClaudeMonitorBridge"
APP="ClaudeMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Helpers"

cp "$BIN" "$APP/Contents/MacOS/ClaudeMonitor"
cp "$BRIDGE" "$APP/Contents/Helpers/ClaudeMonitorBridge"

# Generate the .icns app icon from Resources/AppIcon.png (1024×1024 source).
if [[ -f "Resources/AppIcon.png" ]]; then
    echo "Generating app icon…"
    ICON_TEMP="$(mktemp -d)"
    trap 'rm -rf "$ICON_TEMP"' EXIT
    ICONSET="$ICON_TEMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for sz in 16 32 128 256 512; do
        sips -z $sz $sz       Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}.png"      >/dev/null
        sips -z $((sz*2)) $((sz*2)) Resources/AppIcon.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    mkdir -p "$APP/Contents/Resources"
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeMonitor</string>
    <key>CFBundleDisplayName</key><string>Claude Monitor</string>
    <key>CFBundleIdentifier</key><string>com.local.claudemonitor</string>
    <key>CFBundleExecutable</key><string>ClaudeMonitor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Agent app: lives in the menu bar, no Dock icon. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "Built $APP"

# `make-app.sh --install` installs to ~/Applications (stable location for the
# "Launch at login" toggle) and relaunches it.
if [[ "${1:-}" == "--install" ]]; then
    pkill -f "ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor" 2>/dev/null || true
    sleep 1
    DEST="$HOME/Applications/ClaudeMonitor.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    "$DEST/Contents/Helpers/ClaudeMonitorBridge" --install
    open "$DEST"
    echo "Installed to $DEST and launched."
    echo "Open the menu-bar popover and flip 'Launch at login' once to start at boot."
else
    echo "Run it:  open $APP"
    echo "Enable live updates:  $APP/Contents/Helpers/ClaudeMonitorBridge --install"
    echo "Install + start at login:  ./scripts/make-app.sh --install"
fi
