#!/bin/bash
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="HandsBusy"
LABEL="eu.r3pr3ss10n.handsbusy"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_SRC="$SCRIPT_DIR/$BINARY_NAME"

if [ ! -f "$BINARY_SRC" ]; then
    echo "Error: $BINARY_NAME not found next to this script"
    exit 1
fi

if launchctl list "$LABEL" &>/dev/null; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
fi

sudo mkdir -p "$INSTALL_DIR"
sudo cp "$BINARY_SRC" "$INSTALL_DIR/$BINARY_NAME"
sudo chmod 755 "$INSTALL_DIR/$BINARY_NAME"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$BINARY_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "Installed and running"
