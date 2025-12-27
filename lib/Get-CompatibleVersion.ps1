<#
.SYNOPSIS
    Finds the latest compatible app version using revanced-cli.

.DESCRIPTION
    Uses revanced-cli list-patches to find compatible versions for a specific app.
    Returns the latest version from the list.
#>

param(
    [Parameter(Mandatory)]
    [string]$CliPath,  # Path to revanced-cli.jar

    [Parameter(Mandatory)]
    [string]$RvpPath,  # Path to .rvp patches file

    [Parameter(Mandatory)]
    [string]$PackageName   # e.g., "com.google.android.youtube"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -Object "Finding compatible versions for $PackageName..."

# Run revanced-cli list-patches with version and package filtering
$output = java -jar $CliPath list-patches --with-packages --with-versions --filter-package-name $PackageName $RvpPath 2>&1

# Parse versions from output
# Format: "        19.34.42" (indented version numbers after "Compatible versions:")
$versions = @()
$inVersionBlock = $false

foreach ($line in $output -split "`n") {
    if ($line -match "Compatible versions:") {
        $inVersionBlock = $true
        continue
    }
    
    if ($inVersionBlock) {
        # Version lines are indented with spaces/tabs
        if ($line -match "^\s+(\d+\.\d+\.\d+)\s*$") {
            $versions += $matches[1]
        }
        elseif ($line -match "^\s*$" -or $line -match "^(Index|Name|Description|Enabled|Compatible packages):") {
            # End of version block - reset for next patch
            $inVersionBlock = $false
        }
    }
}

# Get unique versions and sort to find latest
$uniqueVersions = $versions | Sort-Object -Unique

if ($uniqueVersions.Count -eq 0) {
    Write-Host -Object "No version constraints found, using latest"
    return $null
}

# Return the latest compatible version
$latestVersion = $uniqueVersions | Sort-Object { [Version]$_ } -Descending | Select-Object -First 1
Write-Host -Object "Latest compatible version for ${PackageName}: $latestVersion"
return $latestVersion
