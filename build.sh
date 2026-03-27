#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCHEME="HandsBusy"
CONFIG="Release"
BUILD_DIR="$(mktemp -d)"

xcodebuild \
    -project "$ROOT/HandsBusy.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    BUILD_SETTINGS_OVERRIDES="" \
    ONLY_ACTIVE_ARCH=NO

BINARY="$BUILD_DIR/Build/Products/$CONFIG/HandsBusy"

if [ ! -f "$BINARY" ]; then
    echo "Build failed: binary not found"
    rm -rf "$BUILD_DIR"
    exit 1
fi

STAGING="$(mktemp -d)"
cp "$BINARY" "$STAGING/HandsBusy"
cp "$ROOT/install.sh" "$STAGING/install.sh"
rm -rf "$BUILD_DIR"

ZIP="$ROOT/HandsBusy.zip"
(cd "$STAGING" && zip -j "$ZIP" HandsBusy install.sh)
rm -rf "$STAGING"

echo "Ready: $ZIP"
