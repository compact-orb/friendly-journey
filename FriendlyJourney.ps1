<#
.SYNOPSIS
    Main orchestrator for ReVanced patching pipeline.

.DESCRIPTION
    Loads app configuration, checks if repo needs updating, patches all apps,
    updates the F-Droid repository, and syncs to Bunny Storage.
#>

param(
    [string]$ConfigPath = "./apps.yaml",
    [string]$TempPath = "/tmp/friendly-journey",
    [string]$RepoPath = "$TempPath/repo",
    [string]$RepoKeyAlias = "release"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Install powershell-yaml module if not present
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host -Object "Installing powershell-yaml module..."
    Install-Module -Name powershell-yaml -Scope CurrentUser
}
Import-Module -Name powershell-yaml

# Create temp directory
if (-not (Test-Path -Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}

# Create repo directory
if (-not (Test-Path -Path $RepoPath)) {
    New-Item -Path $RepoPath -ItemType Directory | Out-Null
}

# Decode keystores from base64
$ApkKeystorePath = Join-Path -Path $TempPath -ChildPath "Keystore.keystore"
[System.IO.File]::WriteAllBytes($ApkKeystorePath, [Convert]::FromBase64String($env:APK_KEYSTORE_BASE64))
Write-Host -Object "Decoded APK keystore from environment"
$RepoKeystorePath = Join-Path -Path $TempPath -ChildPath "RepoKeystore.keystore"
[System.IO.File]::WriteAllBytes($RepoKeystorePath, [Convert]::FromBase64String($env:REPO_KEYSTORE_BASE64))
Write-Host -Object "Decoded repo keystore from environment"

# Load configuration
Write-Host -Object "Loading configuration from $ConfigPath..."
$configContent = Get-Content -Path $ConfigPath -Raw
$config = ConvertFrom-Yaml -Yaml $configContent
$apps = $config.apps

Write-Host -Object "Found $($apps.Count) app(s) to patch"

# Install tools
Write-Host -Object "`n=== Installing Tools ==="
& "$PSScriptRoot/lib/Install-Tools.ps1" -BinPath "$TempPath/bin"

# Download patches
Write-Host -Object "`n=== Downloading ReVanced Patches ==="
$patchesInfo = & "$PSScriptRoot/lib/Get-RevancedPatches.ps1" -OutputPath $TempPath

# Check if repo is up to date
Write-Host -Object "`n=== Checking Repository Status ==="

# Download entry.json from remote
Write-Host -Object "Checking remote repo on Bunny Storage..."
$remoteEntryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"
& "$PSScriptRoot/lib/Get-BunnyFile.ps1" `
    -RemotePath "repo/entry.json" `
    -LocalPath $remoteEntryPath

# Download latest MicroG for version comparison
Write-Host -Object "`n=== Downloading ReVanced MicroG ==="
$microgInfo = & "$PSScriptRoot/lib/Get-RevancedMicroG.ps1" -OutputPath $TempPath

$isUpToDate = & "$PSScriptRoot/lib/Test-RepoUpToDate.ps1" `
    -RepoPath $RepoPath `
    -LatestPatchesVersion $patchesInfo.Version `
    -LatestMicroGVersion $microgInfo.Version

if ($isUpToDate) {
    Write-Host -Object "Repository is up to date. Nothing to do."
    # Cleanup
    Remove-Item -Path $patchesInfo.SourceZipPath, $patchesInfo.RvpPath
    exit 0
}

# Patch each app
Write-Host -Object "`n=== Patching Apps ==="
foreach ($app in $apps) {
    Write-Host -Object "`n--- Patching $($app.name) ---"

    # Find compatible version
    $compatibleVersion = & "$PSScriptRoot/lib/Get-CompatibleVersion.ps1" `
        -SourceZipPath $patchesInfo.SourceZipPath `
        -PatchesPath $app.patches_path `
        -PackageName $app.package

    # Patch the app
    $patchedApk = & "$PSScriptRoot/lib/Invoke-Patch.ps1" `
        -PackageName $app.package `
        -Version $compatibleVersion `
        -PatchesPath $patchesInfo.RvpPath `
        -OutputPath $TempPath `
        -BinPath "$TempPath/bin"

    # Move to repo
    $repoApkPath = Join-Path -Path $RepoPath -ChildPath "$($app.package).apk"
    Move-Item -Path $patchedApk -Destination $repoApkPath
    Write-Host -Object "Moved to $repoApkPath"
}

# Copy MicroG to repo (already downloaded for version comparison)
Write-Host -Object "`n=== Adding MicroG to Repository ==="
$microgRepoPath = Join-Path -Path $RepoPath -ChildPath "app.revanced.android.gms.apk"
Move-Item -Path $microgInfo.ApkPath -Destination $microgRepoPath -Force
Write-Host -Object "Moved MicroG to $microgRepoPath"

# Update F-Droid repo
Write-Host -Object "`n=== Updating F-Droid Repository ==="
& "$PSScriptRoot/lib/Update-FDroidRepo.ps1" `
    -RepoPath $RepoPath `
    -PatchesVersion $patchesInfo.Version `
    -MicroGVersion $microgInfo.Version `
    -KeystorePath $RepoKeystorePath `
    -KeyAlias $RepoKeyAlias

# Sync to Bunny Storage
Write-Host -Object "`n=== Syncing to Bunny Storage ==="
& "$PSScriptRoot/lib/Sync-BunnyRepo.ps1" `
    -LocalRepoPath $RepoPath

# Cleanup
Write-Host -Object "`n=== Cleanup ==="
Remove-Item -Path $patchesInfo.SourceZipPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $patchesInfo.RvpPath -Force -ErrorAction SilentlyContinue

Write-Host -Object "`n=== Done ==="
Write-Host -Object "Repository updated with patches $($patchesInfo.Version), MicroG $($microgInfo.Version)"
