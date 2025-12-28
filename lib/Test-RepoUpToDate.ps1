<#
.SYNOPSIS
    Checks if the F-Droid repository is up to date.

.DESCRIPTION
    Compares the patches versions (per source) and MicroG version in the repo metadata with the latest releases.
    Also checks if any configured apps are missing from the repo.
    Returns a hashtable with status information.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [hashtable]$LatestSourceVersions,  # @{ "ReVanced/revanced-patches" = "v5.47.0"; "anddea/revanced-patches" = "v3.14.0" }

    [Parameter(Mandatory)]
    [string]$LatestMicroGVersion,

    [Parameter(Mandatory)]
    [string[]]$ConfiguredPackages
)

$ErrorActionPreference = "Stop"

$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"

# Default result for new/missing repo
$result = @{
    IsFullyUpToDate      = $false
    NeedsPatchesUpdate   = $true
    SourcesNeedingUpdate = @($LatestSourceVersions.Keys)
    NeedsMicroGUpdate    = $true
    MissingPackages      = $ConfiguredPackages
}

if (-not (Test-Path -Path $entryPath)) {
    Write-Warning -Message "Repo does not exist, needs creation"
    return $result
}

try {
    $entry = Get-Content -Path $entryPath -Raw | ConvertFrom-Json

    # Handle both old (patchesVersion) and new (sources) schema
    $storedSources = @{}
    if ($entry.sources) {
        # New schema: sources dictionary
        $entry.sources.PSObject.Properties | ForEach-Object {
            $storedSources[$_.Name] = $_.Value
        }
    }
    elseif ($entry.patchesVersion) {
        # Old schema: single patchesVersion (assume official ReVanced)
        $storedSources["ReVanced/revanced-patches"] = $entry.patchesVersion
    }

    $storedMicroGVersion = $entry.microgVersion
    $patchedPackages = $entry.patchedPackages ?? @()

    # Check which sources need updates
    $sourcesNeedingUpdate = @()
    foreach ($source in $LatestSourceVersions.Keys) {
        $storedVersion = $storedSources[$source]
        $latestVersion = $LatestSourceVersions[$source]

        if ($storedVersion -ne $latestVersion) {
            Write-Host -Object "Source '$source' outdated: $storedVersion -> $latestVersion"
            $sourcesNeedingUpdate += $source
        }
        else {
            Write-Host -Object "Source '$source' is up to date: $storedVersion"
        }
    }

    $needsPatchesUpdate = $sourcesNeedingUpdate.Count -gt 0
    $microgMatch = $storedMicroGVersion -eq $LatestMicroGVersion
    $needsMicroGUpdate = -not $microgMatch

    if (-not $microgMatch) {
        Write-Host -Object "MicroG outdated: $storedMicroGVersion -> $LatestMicroGVersion"
    }

    # Find packages that are configured but not yet patched
    $missingPackages = @($ConfiguredPackages | Where-Object { $_ -notin $patchedPackages })

    if ($missingPackages.Count -gt 0) {
        Write-Host -Object "Missing packages: $($missingPackages -join ', ')"
    }

    $isFullyUpToDate = (-not $needsPatchesUpdate) -and (-not $needsMicroGUpdate) -and ($missingPackages.Count -eq 0)

    if ($isFullyUpToDate) {
        $sourcesSummary = ($storedSources.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "
        Write-Host -Object "Repo is up to date (sources: $sourcesSummary, MicroG: $storedMicroGVersion, apps: $($patchedPackages.Count))"
    }

    return @{
        IsFullyUpToDate      = $isFullyUpToDate
        NeedsPatchesUpdate   = $needsPatchesUpdate
        SourcesNeedingUpdate = $sourcesNeedingUpdate
        NeedsMicroGUpdate    = $needsMicroGUpdate
        MissingPackages      = $missingPackages
    }
}
catch {
    Write-Warning -Message "Failed to read repo metadata: $_"
    return $result
}
