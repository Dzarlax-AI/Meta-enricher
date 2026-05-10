# Build a Microsoft Store-ready .msixupload bundle (x64 + ARM64) for MetaEnricher.
#
# Usage (from any PowerShell, in Windows/ folder):
#   .\build-msix.ps1
#
# What it does:
#   1. dotnet publish for win-x64 (self-contained .NET 9 + WindowsAppSDK)
#   2. dotnet publish for win-arm64 (same)
#   3. makeappx bundle: combines both .msix into one .msixbundle
#   4. zip .msixbundle into .msixupload (the Partner Center upload format)
#
# Output: Windows\MetaEnricher_<version>_x64_arm64.msixupload

$ErrorActionPreference = "Stop"

$proj = Join-Path $PSScriptRoot "MetaEnricher\MetaEnricher.csproj"
if (-not (Test-Path $proj)) {
    throw "MetaEnricher.csproj not found at $proj"
}

# Locate makeappx.exe in the Windows 10 SDK.
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$makeappx = $null
if (Test-Path $sdkRoot) {
    $makeappx = Get-ChildItem $sdkRoot -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $makeappx -or -not (Test-Path $makeappx)) {
    throw "makeappx.exe not found in Windows 10 SDK. Install 'Windows 10 SDK' via Visual Studio Installer."
}
Write-Host "makeappx: $makeappx" -ForegroundColor DarkGray

# Wipe stale output.
$binPath = Join-Path $PSScriptRoot "MetaEnricher\bin"
if (Test-Path $binPath) {
    Write-Host "Cleaning $binPath ..." -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $binPath
}

# Read version from manifest so we can name the output file.
$manifestPath = Join-Path $PSScriptRoot "MetaEnricher\Package.appxmanifest"
[xml]$manifest = Get-Content $manifestPath
$pkgVersion = $manifest.Package.Identity.Version
Write-Host "Project:  $proj" -ForegroundColor Cyan
Write-Host "Version:  $pkgVersion" -ForegroundColor Cyan
Write-Host ""

function Publish-Arch {
    param([string]$rid, [string]$platform)
    Write-Host "=== Publish $rid ===" -ForegroundColor Cyan
    & dotnet publish $proj `
        --configuration Release `
        -p:Platform=$platform `
        -p:RuntimeIdentifier=$rid `
        -p:SelfContained=true `
        -p:WindowsAppSDKSelfContained=true `
        -p:WindowsPackageType=MSIX `
        -p:GenerateAppxPackageOnBuild=true `
        -p:AppxBundle=Never `
        -p:UapAppxPackageBuildMode=SideloadOnly `
        -p:AppxSymbolPackageEnabled=false `
        -p:AppxPackageSigningEnabled=false `
        --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $rid (exit $LASTEXITCODE)" }
}

Publish-Arch -rid "win-x64"   -platform "x64"
Publish-Arch -rid "win-arm64" -platform "arm64"

# Find both produced .msix files.
$msixFiles = Get-ChildItem -Path $binPath -Recurse -Filter "MetaEnricher_*.msix" -File `
    | Where-Object { $_.Name -notmatch "scale-" } `
    | Sort-Object LastWriteTime -Descending

$x64Msix   = $msixFiles | Where-Object { $_.Name -match "_x64\.msix$" }   | Select-Object -First 1
$arm64Msix = $msixFiles | Where-Object { $_.Name -match "_arm64\.msix$" } | Select-Object -First 1

if (-not $x64Msix -or -not $arm64Msix) {
    Write-Host "Available .msix files:" -ForegroundColor Red
    $msixFiles | ForEach-Object { Write-Host "  $($_.FullName)" }
    throw "Could not find both _x64.msix and _arm64.msix."
}

Write-Host ""
Write-Host "Packages to bundle:" -ForegroundColor Cyan
Write-Host ("  x64:   {0} ({1} MB)" -f $x64Msix.FullName, [math]::Round($x64Msix.Length/1MB,1))
Write-Host ("  arm64: {0} ({1} MB)" -f $arm64Msix.FullName, [math]::Round($arm64Msix.Length/1MB,1))

# Stage the two .msix files into one folder for makeappx bundle.
$stage = Join-Path $PSScriptRoot "MetaEnricher\bin\BundleStage"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item $x64Msix.FullName   (Join-Path $stage "MetaEnricher_${pkgVersion}_x64.msix")
Copy-Item $arm64Msix.FullName (Join-Path $stage "MetaEnricher_${pkgVersion}_arm64.msix")

$bundlePath = Join-Path $PSScriptRoot "MetaEnricher_${pkgVersion}_x64_arm64.msixbundle"
if (Test-Path $bundlePath) { Remove-Item -Force $bundlePath }

Write-Host ""
Write-Host "=== makeappx bundle ===" -ForegroundColor Cyan
& $makeappx bundle /d $stage /p $bundlePath /bv $pkgVersion /o
if ($LASTEXITCODE -ne 0) { throw "makeappx bundle failed (exit $LASTEXITCODE)" }

# .msixupload is just a zip that contains the .msixbundle.
# Compress-Archive only accepts .zip filename, so zip then rename.
$uploadPath = Join-Path $PSScriptRoot "MetaEnricher_${pkgVersion}_x64_arm64.msixupload"
$tmpZip     = Join-Path $PSScriptRoot "MetaEnricher_${pkgVersion}_x64_arm64.zip"
if (Test-Path $uploadPath) { Remove-Item -Force $uploadPath }
if (Test-Path $tmpZip)     { Remove-Item -Force $tmpZip }
Compress-Archive -Path $bundlePath -DestinationPath $tmpZip -CompressionLevel Optimal
Move-Item -Path $tmpZip -Destination $uploadPath

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ("  Bundle: {0} ({1} MB)" -f $bundlePath, [math]::Round((Get-Item $bundlePath).Length/1MB,1))
Write-Host ("  Upload: {0} ({1} MB)" -f $uploadPath, [math]::Round((Get-Item $uploadPath).Length/1MB,1))
Write-Host ""
Write-Host "Upload the .msixupload to Partner Center." -ForegroundColor Yellow
