<#
.SYNOPSIS
    Installs all required tools for ReVanced patching.

.DESCRIPTION
    Downloads and installs apkeep, APKEditor, and revanced-cli to $BinPath.
    Uses GITHUB_TOKEN for authentication if available.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BinPath
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Create bin directory
if (-not (Test-Path -Path $BinPath)) {
    New-Item -Path $BinPath -ItemType Directory -Force | Out-Null
}

$headers["Authorization"] = "token $env:GITHUB_TOKEN"

function Install-GitHubRelease {
    param(
        [string]$Repo,
        [string]$AssetPattern,
        [string]$DestinationName,
        [switch]$MakeExecutable
    )

    $releasesUrl = "https://api.github.com/repos/$Repo/releases/latest"
    Write-Output -InputObject "Fetching latest release from $Repo..."
    $release = Invoke-RestMethod -Uri $releasesUrl -Headers $headers

    $asset = $release.assets | Where-Object -FilterScript { $_.name -match $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find asset matching '$AssetPattern' in $Repo release $($release.tag_name)"
    }

    $destinationPath = Join-Path -Path $BinPath -ChildPath $DestinationName
    Write-Output -InputObject "Downloading $($asset.name) to $destinationPath..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destinationPath

    if ($MakeExecutable) {
        chmod +x $destinationPath
    }

    Write-Output -InputObject "Installed $DestinationName"
}

# Install apkeep
Install-GitHubRelease -Repo "EFForg/apkeep" `
    -AssetPattern "^apkeep-x86_64-unknown-linux-gnu$" `
    -DestinationName "apkeep" `
    -MakeExecutable

# Install APKEditor
Install-GitHubRelease -Repo "REAndroid/APKEditor" `
    -AssetPattern "^APKEditor-.*\.jar$" `
    -DestinationName "APKEditor.jar"

# Install revanced-cli
Install-GitHubRelease -Repo "ReVanced/revanced-cli" `
    -AssetPattern "^revanced-cli-.*-all\.jar$" `
    -DestinationName "revanced-cli.jar"

Write-Output -InputObject "All tools installed to $BinPath"
