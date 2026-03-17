#!/bin/bash
# Build Go CGO libraries for Windows, Linux, and macOS
# Requires: Go installed

OUTPUT_DIR="./desktop/libs"
PACKAGE_NAME="./desktop"

echo "=== Building Go CGO Libraries for Desktop ==="

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get Go version
echo "Go version: $(go version)"

# Build for Windows (DLL) - only if mingw is available
if command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo -e "\n=== Building Windows DLL ==="
    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
        go build -buildmode=c-shared -o "$OUTPUT_DIR/mimic.dll" "$PACKAGE_NAME"
    if [ $? -eq 0 ]; then
        echo "✓ Windows DLL built successfully: $OUTPUT_DIR/mimic.dll"
    else
        echo "✗ Windows build failed"
    fi
else
    echo -e "\n⊘ Skipping Windows build (mingw-w64 not installed)"
fi

# Build for Linux (SO)
echo -e "\n=== Building Linux SO ==="
CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    go build -buildmode=c-shared -o "$OUTPUT_DIR/libmimic.so" "$PACKAGE_NAME"
if [ $? -eq 0 ]; then
    echo "✓ Linux SO built successfully: $OUTPUT_DIR/libmimic.so"
else
    echo "✗ Linux build failed"
    exit 1
fi

# Build for macOS (DYLIB) - only on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\n=== Building macOS DYLIB ==="
    CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
        go build -buildmode=c-shared -o "$OUTPUT_DIR/libmimic.dylib" "$PACKAGE_NAME"
    if [ $? -eq 0 ]; then
        echo "✓ macOS DYLIB built successfully: $OUTPUT_DIR/libmimic.dylib"
    else
        echo "✗ macOS build failed"
    fi
else
    echo -e "\n⊘ Skipping macOS build (not on macOS)"
fi

echo -e "\n=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo -e "\nFiles created:"
find "$OUTPUT_DIR" -type f 2>/dev/null || echo "No files created"
