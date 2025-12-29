<#
.SYNOPSIS
    Gets the latest available version of an app from APKPure.

.DESCRIPTION
    Uses apkeep --list-versions to query available versions for a package.
    Returns the latest version string which can be used to compare with
    already-patched versions.
#>

param(
    [Parameter(Mandatory)]
    [string]$PackageName,

    [Parameter(Mandatory)]
    [string]$BinPath
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false  # Don't fail on non-zero exit from apkeep

Write-Host -Object "Querying latest version for $PackageName..."

# Run apkeep with --list-versions
$apkeepPath = Join-Path -Path $BinPath -ChildPath "apkeep"
$output = & $apkeepPath --list-versions --app $PackageName 2>&1 | Out-String

# Parse output to find versions
# apkeep --list-versions output format:
#   Versions available for com.spotify.music on APKPure:
#   | 8.9.76.538, 8.9.96.476, 9.0.22.543, ...

$versions = @()
foreach ($line in $output -split "`n") {
    $trimmed = $line.Trim()
    # Match lines starting with pipe containing comma-separated versions
    if ($trimmed -match '^\|(.+)$') {
        $versionList = $Matches[1]
        # Split by comma and clean up each version
        $versionList -split ',' | ForEach-Object {
            $ver = $_.Trim()
            if ($ver -match '^[\d]+\.[\d]+\.[\d]+') {
                $versions += $ver
            }
        }
    }
}

if ($versions.Count -eq 0) {
    Write-Warning -Message "Could not determine latest version for $PackageName"
    return @{
        PackageName = $PackageName
        Version     = $null
    }
}

# Sort versions numerically to find the latest
# Version format: major.minor.patch.build (e.g., 9.1.6.325)
$sortedVersions = $versions | Sort-Object {
    $parts = $_ -split '\.'
    # Create a sortable value: pad each part to 6 digits
    ($parts | ForEach-Object { $_.PadLeft(6, '0') }) -join '.'
} -Descending

$latestVersion = $sortedVersions[0]
Write-Host -Object "Latest version for ${PackageName}: $latestVersion"

return @{
    PackageName = $PackageName
    Version     = $latestVersion
}
