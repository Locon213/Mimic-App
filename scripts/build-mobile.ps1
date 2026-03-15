# Build Go Mobile libraries for Android and iOS
# Requires: gomobile installed (go install golang.org/x/mobile/cmd/gomobile@latest)

param(
    [string]$OutputDir = ".\mobile\libs",
    [string]$PackageName = "github.com/Locon213/Mimic-App/mobile"
)

Write-Host "=== Building Go Mobile Libraries ===" -ForegroundColor Cyan

# Create output directory
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Get Go version
$goVersion = go version
Write-Host "Go version: $goVersion" -ForegroundColor Green

# Initialize gomobile
Write-Host "Initializing gomobile..." -ForegroundColor Yellow
gomobile init

# Build for Android (AAR)
Write-Host "`n=== Building Android AAR ===" -ForegroundColor Cyan
gomobile bind -target android -androidapi 21 -o "$OutputDir\mimic.aar" $PackageName
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Android AAR built successfully: $OutputDir\mimic.aar" -ForegroundColor Green
} else {
    Write-Host "✗ Android build failed" -ForegroundColor Red
    exit 1
}

# Build for iOS (Framework)
Write-Host "`n=== Building iOS Framework ===" -ForegroundColor Cyan
gomobile bind -target ios -iosversion 12.0 -o "$OutputDir\Mimic.xcframework" $PackageName
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ iOS Framework built successfully: $OutputDir\Mimic.xcframework" -ForegroundColor Green
} else {
    Write-Host "✗ iOS build failed" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Output directory: $OutputDir"
Write-Host "`nFiles created:"
Get-ChildItem $OutputDir -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
