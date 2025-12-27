<#
.SYNOPSIS
    Checks if the F-Droid repository is up to date.

.DESCRIPTION
    Compares the patches and MicroG versions in the repo metadata with the latest releases.
    Returns $true if up to date, $false if needs updating.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [string]$LatestPatchesVersion,

    [Parameter(Mandatory)]
    [string]$LatestMicroGVersion
)

$ErrorActionPreference = "Stop"

$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"

if (-not (Test-Path -Path $entryPath)) {
    Write-Warning -Message "Repo does not exist, needs creation"
    return $false
}

try {
    $entry = Get-Content -Path $entryPath -Raw | ConvertFrom-Json

    $storedPatchesVersion = $entry.patchesVersion
    $storedMicroGVersion = $entry.microgVersion

    $patchesMatch = $storedPatchesVersion -eq $LatestPatchesVersion
    $microgMatch = $storedMicroGVersion -eq $LatestMicroGVersion

    if ($patchesMatch -and $microgMatch) {
        Write-Host -Object "Repo is up to date (patches: $storedPatchesVersion, MicroG: $storedMicroGVersion)"
        return $true
    }
    else {
        if (-not $patchesMatch) {
            Write-Host -Object "Patches outdated: $storedPatchesVersion -> $LatestPatchesVersion"
        }
        if (-not $microgMatch) {
            Write-Host -Object "MicroG outdated: $storedMicroGVersion -> $LatestMicroGVersion"
        }
        return $false
    }
}
catch {
    Write-Warning -Message "Failed to read repo metadata: $_"
    return $false
}
