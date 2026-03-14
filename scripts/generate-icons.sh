#!/bin/bash

# Icon Generator Script for Mimic App
# Generates all required icon sizes from a 1024x1024 source icon
# Requires ImageMagick (convert command)

SOURCE_ICON="assets/icon.png"
ICON_1024="assets/icon-1024.png"

# Check if source icon exists
if [ ! -f "$ICON_1024" ]; then
    if [ -f "$SOURCE_ICON" ]; then
        echo "Found source icon: $SOURCE_ICON"
        # Upscale to 1024 if needed
        convert "$SOURCE_ICON" -resize 1024x1024 "$ICON_1024"
    else
        echo "Error: No icon found. Please place icon-1024.png or icon.png in assets/"
        exit 1
    fi
fi

echo "Generating icons from: $ICON_1024"

# Create assets directory if it doesn't exist
mkdir -p assets

# Generate Fyne desktop icons
convert "$ICON_1024" -resize 512x512 assets/icon.png
convert "$ICON_1024" -resize 256x256 assets/icon-256.png
convert "$ICON_1024" -resize 128x128 assets/icon-128.png
convert "$ICON_1024" -resize 64x64 assets/icon-64.png
convert "$ICON_1024" -resize 32x32 assets/icon-32.png
convert "$ICON_1024" -resize 16x16 assets/icon-16.png

# Generate Android adaptive icon layers
# Foreground layer (centered with padding for safe zone)
mkdir -p assets/android/mipmap-hdpi
mkdir -p assets/android/mipmap-xhdpi
mkdir -p assets/android/mipmap-xxhdpi
mkdir -p assets/android/mipmap-xxxhdpi

# Create adaptive icon foreground (108dp with 66dp safe zone)
# The foreground should have the logo centered with transparent padding
convert "$ICON_1024" \
    -background none \
    -gravity center \
    -extent 1200x1200 \
    assets/icon-adaptive-foreground.png

# Create adaptive icon background (solid color or gradient)
convert -size 1200x1200 xc:'#1976D2' assets/icon-adaptive-background.png

# Generate Android launcher icons (with padding for adaptive cropping)
# hdpi: 72x72dp = 108x108px
convert "$ICON_1024" \
    -background none \
    -gravity center \
    -extent 1280x1280 \
    -resize 108x108 \
    assets/android/mipmap-hdpi/ic_launcher.png

# xhdpi: 96x96dp = 144x144px
convert "$ICON_1024" \
    -background none \
    -gravity center \
    -extent 1280x1280 \
    -resize 144x144 \
    assets/android/mipmap-xhdpi/ic_launcher.png

# xxhdpi: 144x144dp = 216x216px
convert "$ICON_1024" \
    -background none \
    -gravity center \
    -extent 1280x1280 \
    -resize 216x216 \
    assets/android/mipmap-xxhdpi/ic_launcher.png

# xxxhdpi: 192x192dp = 288x288px
convert "$ICON_1024" \
    -background none \
    -gravity center \
    -extent 1280x1280 \
    -resize 288x288 \
    assets/android/mipmap-xxxhdpi/ic_launcher.png


echo "✓ Generated Fyne icons:"
ls -la assets/icon*.png

echo ""
echo "✓ Generated Android icons:"
find assets/android -name "*.png"

echo ""
echo "Icon generation complete!"
