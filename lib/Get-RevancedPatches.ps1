<#
.SYNOPSIS
    Downloads the latest ReVanced patches.

.DESCRIPTION
    Downloads the .rvp file from the latest revanced-patches release.
    Returns the patches version and path.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$headers = @{}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "token $env:GITHUB_TOKEN"
}

$repo = "ReVanced/revanced-patches"
$releasesUrl = "https://api.github.com/repos/$repo/releases/latest"

Write-Host -Object "Fetching latest revanced-patches release..."
$release = Invoke-RestMethod -Uri $releasesUrl -Headers $headers

# Download .rvp file
$rvpAsset = $release.assets | Where-Object -FilterScript { $_.name -like "*.rvp" } | Select-Object -First 1
if (-not $rvpAsset) {
    throw "Could not find .rvp asset in release $($release.tag_name)"
}

$rvpPath = Join-Path -Path $OutputPath -ChildPath $rvpAsset.name
Write-Host -Object "Downloading $($rvpAsset.name)..."
Invoke-WebRequest -Uri $rvpAsset.browser_download_url -OutFile $rvpPath

Write-Host -Object "Downloaded patches version: $($release.tag_name)"

# Return version info
return @{
    Version = $release.tag_name
    RvpPath = $rvpPath
}
