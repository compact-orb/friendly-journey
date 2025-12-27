<#
.SYNOPSIS
    Downloads the latest ReVanced GmsCore (MicroG) APK if needed.

.DESCRIPTION
    Fetches the latest release from ReVanced/GmsCore and downloads
    the signed APK. Returns version info for tracking.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$CurrentVersion = "",

    [switch]$CheckVersionOnly
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$headers = @{}
if ($env:GITHUB_TOKEN) {
    $headers["Authorization"] = "token $env:GITHUB_TOKEN"
}

$repo = "ReVanced/GmsCore"
$releasesUrl = "https://api.github.com/repos/$repo/releases/latest"

Write-Host -Object "Fetching latest ReVanced GmsCore release..."
$release = Invoke-RestMethod -Uri $releasesUrl -Headers $headers

$latestVersion = $release.tag_name

# Check if update is needed
if ($CurrentVersion -eq $latestVersion) {
    Write-Host -Object "MicroG is up to date (version: $latestVersion)"
    return @{
        Version   = $latestVersion
        ApkPath   = $null
        IsUpdated = $false
    }
}

if ($CurrentVersion) {
    Write-Host -Object "MicroG update available: $CurrentVersion -> $latestVersion"
}
else {
    Write-Host -Object "MicroG version: $latestVersion"
}

# If only checking version, return without downloading
if ($CheckVersionOnly) {
    return @{
        Version   = $latestVersion
        ApkPath   = $null
        IsUpdated = $true
    }
}

# Find the signed APK (not Huawei variant)
$apkAsset = $release.assets | Where-Object -FilterScript {
    $_.name -like "*-signed.apk" -and $_.name -notlike "*-hw-signed.apk"
} | Select-Object -First 1

$apkPath = Join-Path -Path $OutputPath -ChildPath $apkAsset.name
Write-Host -Object "Downloading $($apkAsset.name)..."
Invoke-WebRequest -Uri $apkAsset.browser_download_url -OutFile $apkPath

Write-Host -Object "Downloaded MicroG version: $latestVersion"

return @{
    Version   = $latestVersion
    ApkPath   = $apkPath
    IsUpdated = $true
}
