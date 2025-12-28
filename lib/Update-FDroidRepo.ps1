<#
.SYNOPSIS
    Updates the F-Droid repository with patched APKs.

.DESCRIPTION
    Uses fdroidserver installed via Python venv to generate and sign the
    F-Droid repository index. Stores patches sources and MicroG versions in entry.json
    for version checking.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [hashtable]$SourceVersions,  # @{ "ReVanced/revanced-patches" = "v5.47.0"; "anddea/revanced-patches" = "v3.14.0" }

    [Parameter(Mandatory)]
    [string]$MicroGVersion,

    [Parameter(Mandatory)]
    [string]$KeystorePath,

    [Parameter(Mandatory)]
    [string]$KeyAlias,

    [Parameter(Mandatory)]
    [string[]]$PatchedPackages,

    [string]$RepoName = "friendly-journey",

    [string]$RepoDescription = "friendly-journey patches Android apps using ReVanced and publishes them to a self-hosted F-Droid repository. It supports automatic updates and syncs to Bunny Storage for CDN distribution."
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Constants
$KeystorePassword = "password"
$VenvPath = "/tmp/friendly-journey/venv"

# Ensure repo directory exists
if (-not (Test-Path -Path $RepoPath)) {
    New-Item -Path $RepoPath -ItemType Directory | Out-Null
}

# Create fdroid directory structure if needed
$fdroidDir = Split-Path -Path $RepoPath -Parent

# Set up Python venv and install fdroidserver
if (-not (Test-Path -Path $VenvPath)) {
    Write-Output -InputObject "Creating Python venv..."
    python3 -m venv $VenvPath
}

# Install fdroidserver if not present
$fdroidBin = Join-Path -Path $VenvPath -ChildPath "bin/fdroid"
if (-not (Test-Path -Path $fdroidBin)) {
    Write-Output -InputObject "Installing fdroidserver..."
    & "$VenvPath/bin/pip" install --upgrade pip
    & "$VenvPath/bin/pip" install fdroidserver
}

# Run fdroid command via venv
function Invoke-Fdroid {
    param([string[]]$Arguments)

    Push-Location -Path $fdroidDir
    try {
        & $fdroidBin @Arguments
    }
    finally {
        Pop-Location
    }
}

# Initialize repo if config.yml doesn't exist
$configPath = Join-Path -Path $fdroidDir -ChildPath "config.yml"
if (-not (Test-Path -Path $configPath)) {
    Write-Output -InputObject "Initializing F-Droid repository..."
    Invoke-Fdroid -Arguments @("init")
}

# Update config.yml with our settings
$configContent = @"
repo_url: $env:FDROID_REPO_URL
repo_name: $RepoName
repo_description: $RepoDescription
archive_older: 0
keystore: $KeystorePath
keystorepass: $KeystorePassword
keypass: $KeystorePassword
repo_keyalias: $KeyAlias
"@

$configContent | Set-Content -Path $configPath
Write-Output -InputObject "Updated config.yml"

# Run fdroid update to generate index
Write-Output -InputObject "Generating F-Droid repository index..."
Invoke-Fdroid -Arguments @("update", "--create-metadata", "--delete-unknown")

Write-Output -InputObject "F-Droid repository updated"

# Write entry.json with sources versions for version checking
$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"
$entry = @{
    sources         = $SourceVersions
    microgVersion   = $MicroGVersion
    patchedPackages = $PatchedPackages
    timestamp       = (Get-Date -Format "o" -AsUTC)
    repoName        = $RepoName
}
$entry | ConvertTo-Json -Depth 3 | Set-Content -Path $entryPath
Write-Output -InputObject "Updated $entryPath"

Write-Output -InputObject "F-Droid repo updated successfully"
