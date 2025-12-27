<#
.SYNOPSIS
    Checks if the F-Droid repository is up to date.

.DESCRIPTION
    Compares the patches and MicroG versions in the repo metadata with the latest releases.
    Also checks if any configured apps are missing from the repo.
    Returns a hashtable with status information.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [string]$LatestPatchesVersion,

    [Parameter(Mandatory)]
    [string]$LatestMicroGVersion,

    [Parameter(Mandatory)]
    [string[]]$ConfiguredPackages
)

$ErrorActionPreference = "Stop"

$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"

# Default result for new/missing repo
$result = @{
    IsFullyUpToDate    = $false
    NeedsPatchesUpdate = $true
    MissingPackages    = $ConfiguredPackages
}

if (-not (Test-Path -Path $entryPath)) {
    Write-Warning -Message "Repo does not exist, needs creation"
    return $result
}

try {
    $entry = Get-Content -Path $entryPath -Raw | ConvertFrom-Json

    $storedPatchesVersion = $entry.patchesVersion
    $storedMicroGVersion = $entry.microgVersion
    $patchedPackages = $entry.patchedPackages ?? @()

    $patchesMatch = $storedPatchesVersion -eq $LatestPatchesVersion
    $microgMatch = $storedMicroGVersion -eq $LatestMicroGVersion
    $needsPatchesUpdate = -not ($patchesMatch -and $microgMatch)

    # Find packages that are configured but not yet patched
    $missingPackages = @($ConfiguredPackages | Where-Object { $_ -notin $patchedPackages })

    if (-not $patchesMatch) {
        Write-Host -Object "Patches outdated: $storedPatchesVersion -> $LatestPatchesVersion"
    }
    if (-not $microgMatch) {
        Write-Host -Object "MicroG outdated: $storedMicroGVersion -> $LatestMicroGVersion"
    }
    if ($missingPackages.Count -gt 0) {
        Write-Host -Object "Missing packages: $($missingPackages -join ', ')"
    }

    $isFullyUpToDate = (-not $needsPatchesUpdate) -and ($missingPackages.Count -eq 0)

    if ($isFullyUpToDate) {
        Write-Host -Object "Repo is up to date (patches: $storedPatchesVersion, MicroG: $storedMicroGVersion, apps: $($patchedPackages.Count))"
    }

    return @{
        IsFullyUpToDate    = $isFullyUpToDate
        NeedsPatchesUpdate = $needsPatchesUpdate
        MissingPackages    = $missingPackages
    }
}
catch {
    Write-Warning -Message "Failed to read repo metadata: $_"
    return $result
}
