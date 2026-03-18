# Build Go CGO libraries for Windows, Linux, and macOS
# Requires: Go installed, MinGW-w64 for Windows build

param(
    [string]$OutputDir = ".\desktop\libs",
    [string]$PackagePath = ".\desktop"
)

Write-Host "=== Building Go CGO Libraries for Desktop ===" -ForegroundColor Cyan

# Create output directory
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Get Go version
$goVersion = go version
Write-Host "Go version: $goVersion" -ForegroundColor Green

# Check if GCC is available
$gccAvailable = Get-Command gcc -ErrorAction SilentlyContinue
if ($null -eq $gccAvailable) {
    Write-Host "⊘ GCC not found. Windows CGO build requires MinGW-w64." -ForegroundColor Yellow
    Write-Host "  Installing via chocolatey or downloading from https://www.mingw-w64.org/" -ForegroundColor Yellow
    exit 1
}

# Build for Windows (DLL)
Write-Host "`n=== Building Windows DLL ===" -ForegroundColor Cyan
$env:CGO_ENABLED = "1"
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CC = "gcc"

go build -buildmode=c-shared -o "$OutputDir\mimic.dll" $PackagePath
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Windows DLL built successfully: $OutputDir\mimic.dll" -ForegroundColor Green
} else {
    Write-Host "✗ Windows build failed" -ForegroundColor Red
    exit 1
}

# Download wintun.dll for TUN mode support
Write-Host "`n=== Downloading wintun.dll ===" -ForegroundColor Cyan
$wintunUrl = "https://www.wintun.net/builds/wintun-0.14.1.zip"
$wintunZip = "$OutputDir\wintun.zip"
$wintunExtracted = "$OutputDir\wintun-extracted"

try {
    Invoke-WebRequest -Uri $wintunUrl -OutFile $wintunZip
    Expand-Archive -Path $wintunZip -DestinationPath $wintunExtracted -Force
    
    # Copy wintun.dll from extracted archive (x64 version)
    $wintunSrc = "$wintunExtracted\wintun\bin\amd64\wintun.dll"
    $wintunDst = "$OutputDir\wintun.dll"
    if (Test-Path $wintunSrc) {
        Copy-Item $wintunSrc $wintunDst -Force
        Write-Host "✓ wintun.dll downloaded and copied to: $wintunDst" -ForegroundColor Green
    } else {
        Write-Host "⊘ wintun.dll not found in archive" -ForegroundColor Yellow
    }
    
    # Cleanup
    Remove-Item $wintunZip -Force -ErrorAction SilentlyContinue
    Remove-Item $wintunExtracted -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "⊘ Failed to download wintun.dll: $_" -ForegroundColor Yellow
    Write-Host "  TUN mode will not work without wintun.dll" -ForegroundColor Yellow
}

# Reset environment
Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\CC -ErrorAction SilentlyContinue

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Output directory: $OutputDir"
Write-Host "`nFiles created:"
Get-ChildItem $OutputDir -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
