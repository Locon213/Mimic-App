#!/bin/bash
# Copy Go CGO library to macOS app bundle
# This script should be run after building the macOS app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Copying Go CGO library to macOS bundle ==="

# Source and destination paths
GO_LIB="$PROJECT_ROOT/desktop/libs/libmimic.dylib"
APP_BUNDLE="$PROJECT_ROOT/mimic_app/build/macos/Build/Products/Release/mimic_app.app/Contents/Frameworks"

if [ -f "$GO_LIB" ]; then
    mkdir -p "$APP_BUNDLE"
    cp "$GO_LIB" "$APP_BUNDLE/"
    echo "✓ Copied libmimic.dylib to $APP_BUNDLE"
else
    echo "⊘ Go library not found at $GO_LIB"
    exit 1
fi
