<#
.SYNOPSIS
    Main orchestrator for ReVanced patching pipeline.

.DESCRIPTION
    Loads app configuration, checks if repo needs updating, patches all apps,
    updates the F-Droid repository, and syncs to Bunny Storage.
#>

param(
    [string]$ConfigPath = "./apps.yaml",
    [string]$RepoPath = "./repo",
    [string]$TempPath = "/tmp/friendly-journey",
    [string]$ApkKeystorePath,
    [string]$RepoKeystorePath,
    [string]$RepoKeyAlias = "release",
    # Bunny Storage parameters (from environment if not specified)
    [string]$BunnyAccessKey,
    [string]$BunnyStorageZone,
    [string]$BunnyEndpoint
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Resolve paths
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = "." }

$ConfigPath = Resolve-Path -Path $ConfigPath -ErrorAction Stop
$RepoPath = Join-Path -Path $ScriptRoot -ChildPath "repo"

# Handle Bunny Storage from environment
if (-not $BunnyAccessKey) { $BunnyAccessKey = $env:BUNNY_STORAGE_ACCESS_KEY }
if (-not $BunnyStorageZone) { $BunnyStorageZone = $env:BUNNY_STORAGE_ZONE_NAME }
if (-not $BunnyEndpoint) { $BunnyEndpoint = $env:BUNNY_STORAGE_ENDPOINT }

$useBunnyStorage = $BunnyAccessKey -and $BunnyStorageZone -and $BunnyEndpoint

# Handle keystore paths - prefer parameters, fall back to base64 env vars, then hardcoded
if (-not $ApkKeystorePath) {
    if ($env:APK_KEYSTORE_BASE64) {
        # Create temp directory first if needed
        if (-not (Test-Path -Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        $ApkKeystorePath = Join-Path -Path $TempPath -ChildPath "Keystore.keystore"
        [System.IO.File]::WriteAllBytes($ApkKeystorePath, [Convert]::FromBase64String($env:APK_KEYSTORE_BASE64))
        Write-Host -Object "Decoded APK keystore from environment"
    }
    else {
        $ApkKeystorePath = Join-Path -Path $ScriptRoot -ChildPath "Keystore.keystore"
    }
}

if (-not $RepoKeystorePath) {
    if ($env:REPO_KEYSTORE_BASE64) {
        # Create temp directory first if needed
        if (-not (Test-Path -Path $TempPath)) {
            New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
        }
        $RepoKeystorePath = Join-Path -Path $TempPath -ChildPath "RepoKeystore.keystore"
        [System.IO.File]::WriteAllBytes($RepoKeystorePath, [Convert]::FromBase64String($env:REPO_KEYSTORE_BASE64))
        Write-Host -Object "Decoded repo keystore from environment"
    }
    else {
        $RepoKeystorePath = Join-Path -Path $ScriptRoot -ChildPath "RepoKeystore.keystore"
    }
}


# Create temp directory
if (-not (Test-Path -Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

# Load configuration
Write-Host -Object "Loading configuration from $ConfigPath..."
$configContent = Get-Content -Path $ConfigPath -Raw
# Simple YAML parsing for our format
$apps = @()
$currentApp = $null

foreach ($line in $configContent -split "`n") {
    if ($line -match "^\s+-\s+name:\s*`"(.+)`"") {
        if ($currentApp) { $apps += $currentApp }
        $currentApp = @{ name = $matches[1] }
    }
    elseif ($line -match "^\s+package:\s*`"(.+)`"" -and $currentApp) {
        $currentApp.package = $matches[1]
    }
    elseif ($line -match "^\s+patches_path:\s*`"(.+)`"" -and $currentApp) {
        $currentApp.patches_path = $matches[1]
    }
}
if ($currentApp) { $apps += $currentApp }

Write-Host -Object "Found $($apps.Count) app(s) to patch"

# Install tools
Write-Host -Object "`n=== Installing Tools ==="
& "$ScriptRoot/lib/Install-Tools.ps1" -BinPath "$TempPath/bin"

# Download patches
Write-Host -Object "`n=== Downloading ReVanced Patches ==="
$patchesInfo = & "$ScriptRoot/lib/Get-RevancedPatches.ps1" -OutputPath $TempPath

# Check if repo is up to date
Write-Host -Object "`n=== Checking Repository Status ==="

# If using Bunny Storage, download entry.json from remote
if ($useBunnyStorage) {
    Write-Host -Object "Checking remote repo on Bunny Storage..."
    if (-not (Test-Path -Path $RepoPath)) {
        New-Item -Path $RepoPath -ItemType Directory -Force | Out-Null
    }
    $remoteEntryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"
    $null = & "$ScriptRoot/lib/Get-BunnyFile.ps1" `
        -RemotePath "repo/entry.json" `
        -LocalPath $remoteEntryPath `
        -AccessKey $BunnyAccessKey `
        -StorageZone $BunnyStorageZone `
        -Endpoint $BunnyEndpoint
}

$isUpToDate = & "$ScriptRoot/lib/Test-RepoUpToDate.ps1" `
    -RepoPath $RepoPath `
    -LatestPatchesVersion $patchesInfo.Version

if ($isUpToDate) {
    Write-Host -Object "Repository is up to date. Nothing to do."
    # Cleanup
    Remove-Item -Path $patchesInfo.SourceZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $patchesInfo.RvpPath -Force -ErrorAction SilentlyContinue
    exit 0
}

# Ensure repo directory exists
if (-not (Test-Path -Path $RepoPath)) {
    New-Item -Path $RepoPath -ItemType Directory -Force | Out-Null
}

# Patch each app
Write-Host -Object "`n=== Patching Apps ==="
foreach ($app in $apps) {
    Write-Host -Object "`n--- Patching $($app.name) ---"

    # Find compatible version
    $compatibleVersion = & "$ScriptRoot/lib/Get-CompatibleVersion.ps1" `
        -SourceZipPath $patchesInfo.SourceZipPath `
        -PatchesPath $app.patches_path `
        -PackageName $app.package

    # Patch the app
    $patchedApk = & "$ScriptRoot/lib/Invoke-Patch.ps1" `
        -PackageName $app.package `
        -Version $compatibleVersion `
        -PatchesPath $patchesInfo.RvpPath `
        -OutputPath $TempPath `
        -BinPath "$TempPath/bin"

    # Move to repo
    $repoApkPath = Join-Path -Path $RepoPath -ChildPath "$($app.package).apk"
    Move-Item -Path $patchedApk -Destination $repoApkPath -Force
    Write-Host -Object "Moved to $repoApkPath"
}

# Update F-Droid repo
Write-Host -Object "`n=== Updating F-Droid Repository ==="
& "$ScriptRoot/lib/Update-FDroidRepo.ps1" `
    -RepoPath $RepoPath `
    -PatchesVersion $patchesInfo.Version `
    -KeystorePath $RepoKeystorePath `
    -KeyAlias $RepoKeyAlias

# Sync to Bunny Storage
if ($useBunnyStorage) {
    Write-Host -Object "`n=== Syncing to Bunny Storage ==="
    & "$ScriptRoot/lib/Sync-BunnyRepo.ps1" `
        -LocalRepoPath $RepoPath `
        -RemoteBasePath "repo" `
        -AccessKey $BunnyAccessKey `
        -StorageZone $BunnyStorageZone `
        -Endpoint $BunnyEndpoint
}
else {
    Write-Host -Object "`n=== Bunny Storage not configured, skipping sync ==="
}

# Cleanup
Write-Host -Object "`n=== Cleanup ==="
Remove-Item -Path $patchesInfo.SourceZipPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $patchesInfo.RvpPath -Force -ErrorAction SilentlyContinue

Write-Host -Object "`n=== Done ==="
Write-Host -Object "Repository updated with patches version $($patchesInfo.Version)"
