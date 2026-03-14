# Icon Generator Script for Mimic App (PowerShell)
# Generates all required icon sizes from a 1024x1024 source icon
# Requires ImageMagick (convert command) - install via: choco install imagemagick

$ErrorActionPreference = "Stop"

$SourceIcon = "assets\icon.png"
$Icon1024 = "assets\icon-1024.png"

# Check if source icon exists
if (-not (Test-Path $Icon1024)) {
    if (Test-Path $SourceIcon) {
        Write-Host "Found source icon: $SourceIcon"
        # Upscale to 1024 if needed
        convert $SourceIcon -resize 1024x1024 $Icon1024
    } else {
        Write-Host "Error: No icon found. Please place icon-1024.png or icon.png in assets/" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Generating icons from: $Icon1024" -ForegroundColor Green

# Create assets directory if it doesn't exist
if (-not (Test-Path "assets")) {
    New-Item -ItemType Directory -Path "assets" | Out-Null
}

# Generate Fyne desktop icons
Write-Host "Generating Fyne desktop icons..."
convert $Icon1024 -resize 512x512 assets\icon.png
convert $Icon1024 -resize 256x256 assets\icon-256.png
convert $Icon1024 -resize 128x128 assets\icon-128.png
convert $Icon1024 -resize 64x64 assets\icon-64.png
convert $Icon1024 -resize 32x32 assets\icon-32.png
convert $Icon1024 -resize 16x16 assets\icon-16.png

# Generate Android adaptive icon layers
Write-Host "Generating Android adaptive icons..."
$androidDirs = @(
    "assets\android\mipmap-hdpi",
    "assets\android\mipmap-xhdpi",
    "assets\android\mipmap-xxhdpi",
    "assets\android\mipmap-xxxhdpi"
)

foreach ($dir in $androidDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

# Create adaptive icon foreground (centered with padding for safe zone)
convert $Icon1024 -background none -gravity center -extent 1200x1200 assets\icon-adaptive-foreground.png

# Create adaptive icon background (solid color - Mimic blue)
convert -size 1200x1200 xc:'#1976D2' assets\icon-adaptive-background.png

# Generate Android launcher icons (with padding for adaptive cropping)
# hdpi: 72x72dp = 108x108px
convert $Icon1024 -background none -gravity center -extent 1200x1200 -resize 108x108 assets\android\mipmap-hdpi\ic_launcher.png

# xhdpi: 96x96dp = 144x144px
convert $Icon1024 -background none -gravity center -extent 1200x1200 -resize 144x144 assets\android\mipmap-xhdpi\ic_launcher.png

# xxhdpi: 144x144dp = 216x216px
convert $Icon1024 -background none -gravity center -extent 1200x1200 -resize 216x216 assets\android\mipmap-xxhdpi\ic_launcher.png

# xxxhdpi: 192x192dp = 288x288px
convert $Icon1024 -background none -gravity center -extent 1200x1200 -resize 288x288 assets\android\mipmap-xxxhdpi\ic_launcher.png

# Generate Play Store icon (512x512)
convert $Icon1024 -resize 512x512 assets\playstore-icon.png

Write-Host "`nGenerated Fyne icons:" -ForegroundColor Cyan
Get-ChildItem assets\icon*.png | Select-Object Name, Length

Write-Host "`nGenerated Android icons:" -ForegroundColor Cyan
Get-ChildItem assets\android\mipmap-*\ic_launcher.png | Select-Object FullName, Length

Write-Host "`nGenerated Play Store icon:" -ForegroundColor Cyan
Get-ChildItem assets\playstore-icon.png | Select-Object Name, Length

Write-Host "`n[OK] Icon generation complete!" -ForegroundColor Green
