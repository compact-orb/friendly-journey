<#
.SYNOPSIS
    Checks if the F-Droid repository is up to date.

.DESCRIPTION
    Compares the patches version in the repo metadata with the latest release.
    Returns $true if up to date, $false if needs updating.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [string]$LatestPatchesVersion
)

$ErrorActionPreference = "Stop"

$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"

if (-not (Test-Path -Path $entryPath)) {
    Write-Warning -Message "Repo does not exist, needs creation"
    return $false
}

try {
    $entry = Get-Content -Path $entryPath -Raw | ConvertFrom-Json
    $storedVersion = $entry.patchesVersion

    if ($storedVersion -eq $LatestPatchesVersion) {
        Write-Output -InputObject "Repo is up to date (patches version: $storedVersion)"
        return $true
    }
    else {
        Write-Output -InputObject "Repo outdated: $storedVersion -> $LatestPatchesVersion"
        return $false
    }
}
catch {
    Write-Warning -Message "Failed to read repo metadata: $_"
    return $false
}
