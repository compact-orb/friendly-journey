<#
.SYNOPSIS
    Updates the F-Droid repository with patched APKs.

.DESCRIPTION
    Uses the official fdroidserver Docker image to generate and sign the
    F-Droid repository index. Stores patches version in entry.json for
    version checking.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [string]$PatchesVersion,

    [string]$KeystorePath,  # Optional: JKS keystore for signing

    [string]$KeyAlias = "release",

    [string]$RepoName = "friendly-journey",

    [string]$RepoDescription = "friendly-journey patched apps"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Constants
$KeystorePassword = "password"
$FdroidImage = "registry.gitlab.com/fdroid/docker-executable-fdroidserver:latest"

# Ensure repo directory exists
if (-not (Test-Path -Path $RepoPath)) {
    New-Item -Path $RepoPath -ItemType Directory -Force | Out-Null
}

# Resolve to absolute path
$RepoPath = Resolve-Path -Path $RepoPath

# Check for container runtime
$containerRuntime = if (Get-Command -Name "podman" -ErrorAction SilentlyContinue) {
    "podman"
}
elseif (Get-Command -Name "docker" -ErrorAction SilentlyContinue) {
    "docker"
}
else {
    throw "Neither podman nor docker found. Please install one of them."
}

Write-Output -InputObject "Using container runtime: $containerRuntime"

# Create fdroid directory structure if needed
$fdroidDir = Split-Path -Path $RepoPath -Parent

# Run fdroid command via container
function Invoke-Fdroid {
    param([string[]]$Arguments)
    
    $mountArgs = @(
        "run", "--rm",
        "-v", "${fdroidDir}:/repo:Z",
        "-w", "/repo"
    )
    
    # Add keystore mount if provided
    if ($KeystorePath -and (Test-Path -Path $KeystorePath)) {
        $keystoreDir = Split-Path -Path $KeystorePath -Parent
        $mountArgs += @("-v", "${keystoreDir}:/keystore:Z")
    }
    
    $mountArgs += $FdroidImage
    $mountArgs += $Arguments
    
    Write-Output -InputObject "Running: $containerRuntime $($Arguments -join ' ')"
    & $containerRuntime @mountArgs
}

# Initialize repo if config.yml doesn't exist
$configPath = Join-Path -Path $fdroidDir -ChildPath "config.yml"
if (-not (Test-Path -Path $configPath)) {
    Write-Output -InputObject "Initializing F-Droid repository..."
    Invoke-Fdroid -Arguments @("init")
}

# Update config.yml with our settings
$configContent = @"
repo_url: https://friendly-journey.compact-orb.ovh/repo
repo_name: $RepoName
repo_description: $RepoDescription
archive_older: 0
"@

# Add keystore config if provided
if ($KeystorePath -and (Test-Path -Path $KeystorePath)) {
    $keystoreName = Split-Path -Path $KeystorePath -Leaf
    $configContent += @"

keystore: /keystore/$keystoreName
keystorepass: $KeystorePassword
keypass: $KeystorePassword
repo_keyalias: $KeyAlias
"@
}

$configContent | Set-Content -Path $configPath
Write-Output -InputObject "Updated config.yml"

# Run fdroid update to generate index
Write-Output -InputObject "Generating F-Droid repository index..."
Invoke-Fdroid -Arguments @("update", "--create-metadata", "--delete-unknown")

Write-Output -InputObject "F-Droid repository updated"

# Write entry.json with patches version for version checking
$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"
$entry = @{
    patchesVersion = $PatchesVersion
    timestamp      = (Get-Date -Format "o")
    repoName       = $RepoName
}
$entry | ConvertTo-Json | Set-Content -Path $entryPath
Write-Output -InputObject "Updated $entryPath"

Write-Output -InputObject "F-Droid repo updated successfully"
