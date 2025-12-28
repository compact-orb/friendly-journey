<#
.SYNOPSIS
    Downloads patches from a specified GitHub-hosted source.

.DESCRIPTION
    Downloads the .rvp file from the latest release of the specified GitHub repo.
    Supports both official ReVanced/revanced-patches and custom sources like anddea/revanced-patches.
    Returns the source, version, and path to the downloaded patches.
#>

param(
    [Parameter(Mandatory)]
    [string]$Source,  # e.g., "anddea/revanced-patches" or "ReVanced/revanced-patches"

    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$headers = @{}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "token $env:GITHUB_TOKEN"
}

# Normalize source name (handle short forms)
$normalizedSource = $Source
if ($Source -eq "official" -or $Source -eq "revanced" -or $Source -eq "ReVanced") {
    $normalizedSource = "ReVanced/revanced-patches"
}
elseif ($Source -eq "anddea") {
    $normalizedSource = "anddea/revanced-patches"
}

$releasesUrl = "https://api.github.com/repos/$normalizedSource/releases/latest"

Write-Host -Object "Fetching latest patches release from $normalizedSource..."
$release = Invoke-RestMethod -Uri $releasesUrl -Headers $headers

# Download .rvp file
$rvpAsset = $release.assets | Where-Object -FilterScript { $_.name -like "*.rvp" } | Select-Object -First 1
if (-not $rvpAsset) {
    throw "Could not find .rvp asset in $normalizedSource release $($release.tag_name)"
}

# Create source-specific subdirectory to avoid collisions
$sourceDir = $normalizedSource -replace "/", "_"
$sourcePath = Join-Path -Path $OutputPath -ChildPath $sourceDir
if (-not (Test-Path -Path $sourcePath)) {
    New-Item -Path $sourcePath -ItemType Directory | Out-Null
}

$rvpPath = Join-Path -Path $sourcePath -ChildPath $rvpAsset.name
Write-Host -Object "Downloading $($rvpAsset.name)..."
Invoke-WebRequest -Uri $rvpAsset.browser_download_url -OutFile $rvpPath

Write-Host -Object "Downloaded patches from $normalizedSource version: $($release.tag_name)"

# Return source info
return @{
    Source  = $normalizedSource
    Version = $release.tag_name
    RvpPath = $rvpPath
}
