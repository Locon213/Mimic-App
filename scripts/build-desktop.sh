#!/bin/bash
# Build Go CGO libraries for desktop platforms
# Builds only for the current platform

OUTPUT_DIR="./desktop/libs"
PACKAGE_NAME="./desktop"

echo "=== Building Go CGO Libraries for Desktop ==="

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get Go version
echo "Go version: $(go version)"
echo "Current OS: $(uname -s)"

# Build based on current platform
case "$(uname -s)" in
    Linux*)
        echo -e "\n=== Building Linux SO ==="
        CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
            go build -buildmode=c-shared -o "$OUTPUT_DIR/libmimic.so" "$PACKAGE_NAME"
        if [ $? -eq 0 ]; then
            echo "✓ Linux SO built successfully: $OUTPUT_DIR/libmimic.so"
        else
            echo "✗ Linux build failed"
            exit 1
        fi
        ;;
    Darwin*)
        echo -e "\n=== Building macOS DYLIB ==="
        CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
            go build -buildmode=c-shared -o "$OUTPUT_DIR/libmimic.dylib" "$PACKAGE_NAME"
        if [ $? -eq 0 ]; then
            echo "✓ macOS DYLIB built successfully: $OUTPUT_DIR/libmimic.dylib"
        else
            echo "✗ macOS build failed"
            exit 1
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo -e "\n=== Building Windows DLL ==="
        CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=gcc \
            go build -buildmode=c-shared -o "$OUTPUT_DIR/mimic.dll" "$PACKAGE_NAME"
        if [ $? -eq 0 ]; then
            echo "✓ Windows DLL built successfully: $OUTPUT_DIR/mimic.dll"
        else
            echo "✗ Windows build failed"
            exit 1
        fi
        ;;
    *)
        echo "Unsupported platform: $(uname -s)"
        exit 1
        ;;
esac

echo -e "\n=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo -e "\nFiles created:"
find "$OUTPUT_DIR" -type f 2>/dev/null || echo "No files created"
