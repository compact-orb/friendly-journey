<#
.SYNOPSIS
    Downloads the latest ReVanced patches and extracts source for version discovery.

.DESCRIPTION
    Downloads the .rvp file and source zip from the latest revanced-patches release.
    Returns the patches version tag.
#>

param(
    [string]$OutputPath = "/tmp/friendly-journey"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$headers = @{}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "token $env:GITHUB_TOKEN"
}

$repo = "ReVanced/revanced-patches"
$releasesUrl = "https://api.github.com/repos/$repo/releases/latest"

Write-Output -InputObject "Fetching latest revanced-patches release..."
$release = Invoke-RestMethod -Uri $releasesUrl -Headers $headers

# Download .rvp file
$rvpAsset = $release.assets | Where-Object -Process { $_.name -like "*.rvp" } | Select-Object -First 1
if (-not $rvpAsset) {
    throw "Could not find .rvp asset in release $($release.tag_name)"
}

# Create output directory if needed
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$rvpPath = Join-Path -Path $OutputPath -ChildPath $rvpAsset.name
Write-Output -InputObject "Downloading $($rvpAsset.name)..."
Invoke-WebRequest -Uri $rvpAsset.browser_download_url -OutFile $rvpPath

# Download source zip for version discovery
$sourceZipName = "patches-$($release.tag_name)-source.zip"
$sourceZipPath = Join-Path -Path $OutputPath -ChildPath $sourceZipName
Write-Output -InputObject "Downloading source zip..."
Invoke-WebRequest -Uri $release.zipball_url -OutFile $sourceZipPath -Headers $headers

Write-Output -InputObject "Downloaded patches version: $($release.tag_name)"

# Return version info
return @{
    Version       = $release.tag_name
    RvpPath       = $rvpPath
    SourceZipPath = $sourceZipPath
}

