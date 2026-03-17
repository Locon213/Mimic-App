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

# Reset environment
Remove-Item Env:\CGO_ENABLED -ErrorAction SilentlyContinue
Remove-Item Env:\GOOS -ErrorAction SilentlyContinue
Remove-Item Env:\GOARCH -ErrorAction SilentlyContinue
Remove-Item Env:\CC -ErrorAction SilentlyContinue

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Output directory: $OutputDir"
Write-Host "`nFiles created:"
Get-ChildItem $OutputDir -Recurse -File | ForEach-Object { Write-Host "  $($_.FullName)" }
