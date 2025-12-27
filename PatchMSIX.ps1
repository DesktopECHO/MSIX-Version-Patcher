<#
.SYNOPSIS
    Automated tool for modifying MSIX/APPX TargetDeviceFamily constraints.

.DESCRIPTION
    PatchMSIX.ps1 extracts a package, modifies the AppxManifest to match a 
    target version, rebuilds, signs with a self-signed certificate, and deploys.

.NOTES
    File Name      : PatchMSIX.ps1
    Author         : Daniel Milisic (DesktopECHO)
    Version        : 1.4 (Full APPX/MSIX Compatibility)
    Prerequisites  : Administrative Privileges, MSIX Packaging Tool.
#>

Clear-Host
Write-Host ("=" * 60) -ForegroundColor Gray
Write-Host "               PACKAGE VERSION PATCHER" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Gray

# --- 0/10. Admin Elevation Check ---
Write-Host "[0/10] Verifying Administrative Privileges..." -ForegroundColor Cyan
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    return
}

# --- Initialization & Version Prompt ---
$sdkPath       = "C:\ProgramData\PatchMSIX\SDK"
$workDir       = "C:\ProgramData\PatchMSIX\Work"
$outputDir     = "C:\ProgramData\PatchMSIX"
$pfxPassword   = "SelfSigned"
$timestampUrl  = "http://timestamp.digicert.com"

# Determine default OS build
$osBuild = [System.Environment]::OSVersion.Version.Build.ToString()
Write-Host "`nCurrent OS Build detected: $osBuild" -ForegroundColor Yellow
$userInput = Read-Host "Enter target build version (or press ENTER to use $osBuild)"

# Set newVersion based on input
$newVersion = if ([string]::IsNullOrWhiteSpace($userInput)) { $osBuild } else { $userInput }
Write-Host "Target Version set to: $newVersion`n" -ForegroundColor Green

# --- 1/10. SDK Synchronizing ---
Write-Host "[1/10] Synchronizing SDK Toolset..." -ForegroundColor Cyan
$makeAppxPath = Join-Path $sdkPath "makeappx.exe"
$signToolPath = Join-Path $sdkPath "signtool.exe"

if (-not (Test-Path $makeAppxPath) -or -not (Test-Path $signToolPath)) {
    $Package = Get-AppxPackage | Where-Object { $_.Name -like "*Microsoft.MsixPackagingTool*" }
    if ($null -eq $Package) { Write-Host "Error: MSIX Packaging Tool not found!" -ForegroundColor Red; return }
    $binSource = Get-ChildItem -Path $Package.InstallLocation -Filter "makeappx.exe" -Recurse | 
                 Where-Object { $_.FullName -match "x64" } | Select-Object -First 1 -ExpandProperty DirectoryName
    if ($binSource) {
        if (-not (Test-Path $sdkPath)) { New-Item -ItemType Directory -Path $sdkPath -Force | Out-Null }
        Copy-Item -Path "$binSource\*" -Destination $sdkPath -Recurse -Force
    }
}

# --- 2/10. Source Selection ---
Write-Host "[2/10] Awaiting source file selection..." -ForegroundColor Cyan
Add-Type -AssemblyName System.Windows.Forms
$FilterStr = "App Packages (*.msix;*.msixbundle;*.appx;*.appxbundle)|*.msix;*.msixbundle;*.appx;*.appxbundle"
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ Filter = $FilterStr }
if ($FileBrowser.ShowDialog() -ne "OK") { return }
$inputPath = $FileBrowser.FileName
$isBundle  = $inputPath.EndsWith(".msixbundle", "OrdinalIgnoreCase") -or $inputPath.EndsWith(".appxbundle", "OrdinalIgnoreCase")

# --- 3/10. Staging Environment Setup ---
Write-Host "[3/10] Initializing staging environment..." -ForegroundColor Cyan
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue }
$extractDir = New-Item -ItemType Directory -Path (Join-Path $workDir "Extracted") -Force
$tempPfx    = Join-Path $workDir "TempCert.pfx"

# --- 4/10. Payload Extraction ---
Write-Host "[4/10] Extracting package payload..." -ForegroundColor Cyan
if ($isBundle) { & "$makeAppxPath" unbundle /p "$inputPath" /d "$extractDir" /o | Out-Null } 
else { & "$makeAppxPath" unpack /p "$inputPath" /d "$extractDir" /o | Out-Null }

# --- 5/10. Metadata Parsing ---
Write-Host "[5/10] Parsing package metadata..." -ForegroundColor Cyan
$targetManifest = if ($isBundle) { Join-Path $extractDir "AppxMetadata\AppxBundleManifest.xml" } else { Join-Path $extractDir "AppxManifest.xml" }
if (-not (Test-Path $targetManifest)) { Write-Host "Critical Error: Extraction failed!" -ForegroundColor Red; return }

[xml]$xmlData = Get-Content $targetManifest
$identityNode = $xmlData.SelectSingleNode("//*[local-name()='Identity']")
$publisherName = $identityNode.Publisher
$packageName   = $identityNode.Name

$tdfNode = $xmlData.SelectSingleNode("//*[local-name()='TargetDeviceFamily']")
$originalFullVersion = $tdfNode.MinVersion
$originalBuild = if ($null -eq $originalFullVersion) { "Unknown" } else { $originalFullVersion.Split('.')[2] }

# --- 6/10. Manifest Patching ---
Write-Host "[6/10] Injecting Build $newVersion into manifests..." -ForegroundColor Cyan
$rawXml = Get-Content $targetManifest -Raw
$updatedXml = $rawXml -replace '(TargetDeviceFamily.*?MinVersion="\d+\.\d+\.)(\d+)(\.\d+")', "`${1}$newVersion`${3}"
[System.IO.File]::WriteAllText($targetManifest, $updatedXml, (New-Object System.Text.UTF8Encoding $false))

if ($isBundle) {
    Get-ChildItem $extractDir -Include "*.msix", "*.appx" -Recurse | ForEach-Object {
        Write-Host "   -> Patching embedded package: $($_.Name)" -ForegroundColor Gray
        $innerDir = Join-Path $workDir $_.BaseName
        & "$makeAppxPath" unpack /p $_.FullName /d $innerDir /o | Out-Null
        $innerM = Join-Path $innerDir "AppxManifest.xml"
        $innerXml = (Get-Content $innerM -Raw) -replace '(TargetDeviceFamily.*?MinVersion="\d+\.\d+\.)(\d+)(\.\d+")', "`${1}$newVersion`${3}"
        [System.IO.File]::WriteAllText($innerM, $innerXml, (New-Object System.Text.UTF8Encoding $false))
        if (Test-Path (Join-Path $innerDir "AppxSignature.p7x")) { Remove-Item (Join-Path $innerDir "AppxSignature.p7x") -Force }
        Remove-Item $_.FullName -Force
        & "$makeAppxPath" pack /d $innerDir /p $_.FullName /o | Out-Null
        Remove-Item $innerDir -Recurse -Force
    }
}

# --- 7/10. Certificate Generation ---
Write-Host "[7/10] Generating ephemeral signing certificate..." -ForegroundColor Cyan
$friendlyName = "Package_Patch_$packageName"
$cert = New-SelfSignedCertificate -Type Custom -Subject "$publisherName" -KeyUsage DigitalSignature -FriendlyName $friendlyName -CertStoreLocation "Cert:\LocalMachine\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
$securePassword = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$tempPfx" -Password $securePassword | Out-Null
Import-PfxCertificate -FilePath "$tempPfx" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -Password $securePassword | Out-Null
Start-Sleep -Seconds 2

# --- 8/10. Rebuilding & Signing ---
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
$extension = [System.IO.Path]::GetExtension($inputPath)
$newFileName = $baseName + "_Patched" + $extension
$newPfxName = $baseName + "_Patched.pfx"

$newPath = Join-Path $outputDir $newFileName
$finalPfxPath = Join-Path $outputDir $newPfxName

Write-Host "[8/10] Rebuilding and signing binary..." -ForegroundColor Cyan
if ($isBundle) { & "$makeAppxPath" bundle /d "$extractDir" /p "$newPath" /o | Out-Null } 
else { & "$makeAppxPath" pack /d "$extractDir" /p "$newPath" /o | Out-Null }
& "$signToolPath" sign /f "$tempPfx" /p $pfxPassword /fd SHA256 /tr $timestampUrl /td SHA256 "$newPath" | Out-Null

Move-Item -Path $tempPfx -Destination $finalPfxPath -Force

# --- 9/10. Collision Resolution ---
Write-Host "[9/10] Resolving package naming collisions..." -ForegroundColor Cyan
$existing = Get-AppxPackage -Name $packageName
if ($existing) { 
    Write-Host "   -> De-registering existing build: $($existing.PackageFullName)" -ForegroundColor Gray
    Remove-AppxPackage -Package $existing.PackageFullName 
}

# --- 10/10. Deployment ---
Write-Host "[10/10] Deploying patched package to OS..." -ForegroundColor Green
Add-AppxPackage -Path "$newPath"

# Final Cleanup of Work Directory
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue }

# --- FINAL SUMMARY ---
$fullOutputPath = (Resolve-Path $newPath).Path
$fullPfxPath = (Resolve-Path $finalPfxPath).Path

Write-Host "`n"
Write-Host ("=" * 60) -ForegroundColor Gray
Write-Host "                 BUILD SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Gray
Write-Host " Identity:         $packageName"
Write-Host " Source Build:     $originalBuild" -ForegroundColor Red
Write-Host " Target Build:     $newVersion" -ForegroundColor Green
Write-Host " PFX Password:     $pfxPassword" -ForegroundColor Yellow
Write-Host " Binary Path:      $fullOutputPath"
Write-Host " Certificate:      $fullPfxPath"
Write-Host ("=" * 60) -ForegroundColor Gray
Write-Host "Process Complete. Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
