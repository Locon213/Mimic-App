#!/bin/bash
# Build Go Mobile libraries for Android and iOS
# Requires: gomobile installed (go install golang.org/x/mobile/cmd/gomobile@latest)

OUTPUT_DIR="./mobile/libs"
PACKAGE_NAME="github.com/Locon213/Mimic-App/mobile"

echo "=== Building Go Mobile Libraries ==="

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get Go version
echo "Go version: $(go version)"

# Initialize gomobile and install required packages
echo "Initializing gomobile..."
gomobile init

# Install required gomobile dependencies
echo "Installing gomobile dependencies..."
go get golang.org/x/mobile/bind@latest

# Build for Android (AAR)
echo -e "\n=== Building Android AAR ==="
gomobile bind -target android -androidapi 21 -o "$OUTPUT_DIR/mimic.aar" "$PACKAGE_NAME"
if [ $? -eq 0 ]; then
    echo "✓ Android AAR built successfully: $OUTPUT_DIR/mimic.aar"
else
    echo "✗ Android build failed"
    exit 1
fi

# Build for iOS (Framework)
echo -e "\n=== Building iOS Framework ==="
gomobile bind -target ios -iosversion 12.0 -o "$OUTPUT_DIR/Mimic.xcframework" "$PACKAGE_NAME"
if [ $? -eq 0 ]; then
    echo "✓ iOS Framework built successfully: $OUTPUT_DIR/Mimic.xcframework"
else
    echo "✗ iOS build failed"
    exit 1
fi

echo -e "\n=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo -e "\nFiles created:"
find "$OUTPUT_DIR" -type f
