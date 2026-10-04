#requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " SkyCraft Native Build" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Locate Visual Studio / Build Tools
# ------------------------------------------------------------

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe was not found at: $vswhere"
}

$vsPath = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Workload.VCTools `
    -property installationPath

if (-not $vsPath) {
    throw "Visual Studio installation with the C++ workload was not found."
}

$vsPath = $vsPath.Trim()

Write-Host "Visual Studio:" -ForegroundColor Green
Write-Host "  $vsPath"
Write-Host ""

# ------------------------------------------------------------
# Initialize MSVC x64 environment
# ------------------------------------------------------------

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"

if (-not (Test-Path $vcvars)) {
    throw "vcvars64.bat was not found: $vcvars"
}

Write-Host "Initializing MSVC x64 environment..." -ForegroundColor Yellow

cmd.exe /c "`"$vcvars`" && set" |
    ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
        }
    }

# ------------------------------------------------------------
# Verify compiler
# ------------------------------------------------------------

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue

if (-not $cl) {
    throw "MSVC compiler (cl.exe) could not be found after initializing vcvars64.bat."
}

Write-Host ""
Write-Host "Compiler:" -ForegroundColor Green
Write-Host "  $($cl.Source)"
Write-Host "  MSVC compiler detected successfully." -ForegroundColor Green

# ------------------------------------------------------------
# Verify CMake
# ------------------------------------------------------------

$cmake = Get-Command cmake.exe -ErrorAction SilentlyContinue

if (-not $cmake) {
    throw @"
CMake was not found.

Install CMake with:

    winget install --id Kitware.CMake -e

Then run this script again.
"@
}

Write-Host ""
Write-Host "CMake:" -ForegroundColor Green
Write-Host "  $($cmake.Source)"
Write-Host ""

# ------------------------------------------------------------
# Locate SkyCraft source
# ------------------------------------------------------------

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "SkyCraft directory:" -ForegroundColor Green
Write-Host "  $RootDir"
Write-Host ""

# Look for CMakeLists.txt in the source tree.
# The native project may be inside a subdirectory.

$CMakeFile = Get-ChildItem `
    -Path $RootDir `
    -Filter "CMakeLists.txt" `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $CMakeFile) {
    throw @"
No CMakeLists.txt was found anywhere under:

    $RootDir

Make sure this is the actual SkyCraft source tree rather than
the packaged/mod ZIP contents.
"@
}

$SourceDir = $CMakeFile.Directory.FullName

Write-Host "Native CMake project:" -ForegroundColor Green
Write-Host "  $SourceDir"
Write-Host ""

# ------------------------------------------------------------
# Build directory
# ------------------------------------------------------------

$BuildDir = Join-Path $SourceDir "build"

if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# ------------------------------------------------------------
# Configure
# ------------------------------------------------------------

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Configuring CMake" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

& cmake.exe `
    -S $SourceDir `
    -B $BuildDir `
    -G "Visual Studio 18 2026" `
    -A x64

if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed."
}

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Building SkyCraft" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

& cmake.exe `
    --build $BuildDir `
    --config Release `
    --parallel

if ($LASTEXITCODE -ne 0) {
    throw "SkyCraft native build failed."
}

# ------------------------------------------------------------
# Find resulting DLL
# ------------------------------------------------------------

Write-Host ""
Write-Host "Searching for SkyCraft.dll..." -ForegroundColor Yellow

$dll = Get-ChildItem `
    -Path $BuildDir `
    -Filter "SkyCraft.dll" `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $dll) {
    Write-Warning "CMake reported a successful build, but SkyCraft.dll was not found automatically."
    Write-Host ""
    Write-Host "Build directory:"
    Write-Host "  $BuildDir"
    exit 0
}

# ------------------------------------------------------------
# Success
# ------------------------------------------------------------

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " BUILD SUCCESSFUL" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

Write-Host "SkyCraft.dll:"
Write-Host "  $($dll.FullName)"
Write-Host ""

Write-Host "Size:"
Write-Host "  $($dll.Length) bytes"
Write-Host ""

$hash = Get-FileHash $dll.FullName -Algorithm SHA256

Write-Host "SHA-256:"
Write-Host "  $($hash.Hash)"
Write-Host ""

Write-Host "Native build completed successfully." -ForegroundColor Green
Write-Host ""