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
    [string]$RepoKeyAlias = "release"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Install powershell-yaml module if not present
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host -Object "Installing powershell-yaml module..."
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force
}
Import-Module -Name powershell-yaml

# Create temp directory
if (-not (Test-Path -Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}

$repoPath = Join-Path -Path $TempPath -ChildPath "repo"

# Create repo directory
if (-not (Test-Path -Path $repoPath)) {
    New-Item -Path $repoPath -ItemType Directory | Out-Null
}

# Decode keystores from base64
$ApkKeystorePath = Join-Path -Path $TempPath -ChildPath "Keystore.keystore"
[System.IO.File]::WriteAllBytes($ApkKeystorePath, [Convert]::FromBase64String($env:APK_KEYSTORE_BASE64))
Write-Host -Object "Decoded APK keystore from environment"
$RepoKeystorePath = Join-Path -Path $TempPath -ChildPath "RepoKeystore.keystore"
[System.IO.File]::WriteAllBytes($RepoKeystorePath, [Convert]::FromBase64String($env:REPO_KEYSTORE_BASE64))
Write-Host -Object "Decoded repo keystore from environment"

# Define local APK download path
$LocalApkPath = Join-Path -Path $PSScriptRoot -ChildPath "downloads"
if (-not (Test-Path -Path $LocalApkPath)) {
    New-Item -Path $LocalApkPath -ItemType Directory | Out-Null
}

# Load configuration
Write-Host -Object "Loading configuration from $ConfigPath..."
$configContent = Get-Content -Path $ConfigPath -Raw
$config = ConvertFrom-Yaml -Yaml $configContent
$apps = $config.apps

Write-Host -Object "Found $($apps.Count) app(s) to patch"

$binPath = Join-Path -Path $TempPath -ChildPath "bin"

# Install tools
Write-Host -Object "`n=== Installing Tools ==="
& "$PSScriptRoot/lib/Install-Tools.ps1" -BinPath "$binPath"

# Download patches
Write-Host -Object "`n=== Downloading ReVanced Patches ==="
$patchesInfo = & "$PSScriptRoot/lib/Get-RevancedPatches.ps1" -OutputPath $TempPath

# Check if repo is up to date
Write-Host -Object "`n=== Checking Repository Status ==="

# Download entry.json from remote
Write-Host -Object "Checking remote repo on Bunny Storage..."
$remoteEntryPath = Join-Path -Path $repoPath -ChildPath "entry.json"
$null = & "$PSScriptRoot/lib/Get-BunnyFile.ps1" `
    -RemotePath "repo/entry.json" `
    -LocalPath $remoteEntryPath

# Download latest MicroG for version comparison
Write-Host -Object "`n=== Downloading ReVanced MicroG ==="
$microgInfo = & "$PSScriptRoot/lib/Get-RevancedMicroG.ps1" -OutputPath $TempPath

# Extract configured package names
$configuredPackages = @($apps | ForEach-Object { $_.package })

$repoStatus = & "$PSScriptRoot/lib/Test-RepoUpToDate.ps1" `
    -RepoPath $repoPath `
    -LatestPatchesVersion $patchesInfo.Version `
    -LatestMicroGVersion $microgInfo.Version `
    -ConfiguredPackages $configuredPackages

if ($repoStatus.IsFullyUpToDate) {
    Write-Host -Object "Repository is up to date. Nothing to do."
    # Cleanup
    Remove-Item -Path $patchesInfo.RvpPath
    exit 0
}

# Determine which apps to patch
if ($repoStatus.NeedsPatchesUpdate) {
    # Patches/MicroG changed - repatch all apps
    Write-Host -Object "Patches or MicroG updated, will repatch all apps"
    $appsToPatch = $apps
}
else {
    # Only patch missing apps
    Write-Host -Object "Only patching new apps: $($repoStatus.MissingPackages -join ', ')"
    $appsToPatch = @($apps | Where-Object { $_.package -in $repoStatus.MissingPackages })
}

# Patch selected apps
Write-Host -Object "`n=== Patching Apps ==="
$patchedPackages = @()

foreach ($app in $appsToPatch) {
    Write-Host -Object "`n--- Patching $($app.name) ---"

    # Find compatible version using revanced-cli
    $compatibleVersion = & "$PSScriptRoot/lib/Get-CompatibleVersion.ps1" `
        -CliPath "$TempPath/bin/revanced-cli.jar" `
        -RvpPath $patchesInfo.RvpPath `
        -PackageName $app.package

    # Patch the app
    $patchedApks = & "$PSScriptRoot/lib/Invoke-Patch.ps1" `
        -PackageName $app.package `
        -Version $compatibleVersion `
        -PatchesPath $patchesInfo.RvpPath `
        -OutputPath $TempPath `
        -BinPath "$TempPath/bin" `
        -KeystorePath $ApkKeystorePath `
        -LocalApkPath $LocalApkPath `
        -IncludePatches ($app.include ?? @()) `
        -ExcludePatches ($app.exclude ?? @())

    # Move all patched APKs to repo
    foreach ($apk in $patchedApks) {
        if (-not (Test-Path $apk)) { continue }

        $apkName = [System.IO.Path]::GetFileName($apk)
        # Unique naming to avoid collisions if not already handled
        # (Invoke-Patch adds original filename which includes arch usually)

        $repoApkPath = Join-Path -Path $repoPath -ChildPath $apkName
        Move-Item -Path $apk -Destination $repoApkPath -Force
        Write-Host -Object "Moved to $repoApkPath"
    }

    # Track this package as patched
    $patchedPackages += $app.package
}

# Combine with existing patched packages if we're only adding new apps
if (-not $repoStatus.NeedsPatchesUpdate) {
    # Read existing patched packages from entry.json
    $entryPath = Join-Path -Path $repoPath -ChildPath "entry.json"
    if (Test-Path -Path $entryPath) {
        $existingEntry = Get-Content -Path $entryPath -Raw | ConvertFrom-Json
        $existingPackages = $existingEntry.patchedPackages ?? @()
        $patchedPackages = @($existingPackages) + $patchedPackages | Select-Object -Unique
    }
}
else {
    # We're repatching all, so use all configured packages
    $patchedPackages = $configuredPackages
}

# Copy MicroG to repo (already downloaded for version comparison)
Write-Host -Object "`n=== Adding MicroG to Repository ==="
$microgRepoPath = Join-Path -Path $repoPath -ChildPath "app.revanced.android.gms.apk"
Move-Item -Path $microgInfo.ApkPath -Destination $microgRepoPath -Force
Write-Host -Object "Moved MicroG to $microgRepoPath"

# Update F-Droid repo
Write-Host -Object "`n=== Updating F-Droid Repository ==="
& "$PSScriptRoot/lib/Update-FDroidRepo.ps1" `
    -RepoPath $repoPath `
    -PatchesVersion $patchesInfo.Version `
    -MicroGVersion $microgInfo.Version `
    -KeystorePath $RepoKeystorePath `
    -KeyAlias $RepoKeyAlias `
    -PatchedPackages $patchedPackages

# Sync to Bunny Storage
Write-Host -Object "`n=== Syncing to Bunny Storage ==="
& "$PSScriptRoot/lib/Sync-BunnyRepo.ps1" `
    -LocalRepoPath $repoPath `
    -RemotePrefix "repo"

# Cleanup
Write-Host -Object "`n=== Cleanup ==="
Remove-Item -Path $patchesInfo.RvpPath -Force -ErrorAction SilentlyContinue

Write-Host -Object "`n=== Done ==="
Write-Host -Object "Repository updated with patches $($patchesInfo.Version), MicroG $($microgInfo.Version)"
