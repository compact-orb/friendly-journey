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
    [string[]]$ConfiguredPackages,

    [hashtable]$LatestAppVersions = @{}  # @{ "com.spotify.music" = "9.0.0.487" } for apps without version constraints
)

$ErrorActionPreference = "Stop"

$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"

# Default result for new/missing repo
$result = @{
    IsFullyUpToDate              = $false
    NeedsPatchesUpdate           = $true
    SourcesNeedingUpdate         = @($LatestSourceVersions.Keys)
    NeedsMicroGUpdate            = $true
    MissingPackages              = $ConfiguredPackages
    PackagesNeedingVersionUpdate = @($LatestAppVersions.Keys)
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

    # Check for version updates on apps without constraints
    $storedVersions = @{}
    if ($entry.packageVersions) {
        $entry.packageVersions.PSObject.Properties | ForEach-Object {
            $storedVersions[$_.Name] = $_.Value
        }
    }

    $packagesNeedingVersionUpdate = @()
    foreach ($pkg in $LatestAppVersions.Keys) {
        $storedVersion = $storedVersions[$pkg]
        $latestVersion = $LatestAppVersions[$pkg]

        if (-not $storedVersion) {
            # No stored version - will be handled by missing packages or first patch
            continue
        }

        if ($storedVersion -ne $latestVersion) {
            Write-Host -Object "App '$pkg' has newer version: $storedVersion -> $latestVersion"
            $packagesNeedingVersionUpdate += $pkg
        }
        else {
            Write-Host -Object "App '$pkg' version is current: $storedVersion"
        }
    }

    $isFullyUpToDate = (-not $needsPatchesUpdate) -and `
    (-not $needsMicroGUpdate) -and `
    ($missingPackages.Count -eq 0) -and `
    ($packagesNeedingVersionUpdate.Count -eq 0)

    if ($isFullyUpToDate) {
        $sourcesSummary = ($storedSources.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", "
        Write-Host -Object "Repo is up to date (sources: $sourcesSummary, MicroG: $storedMicroGVersion, apps: $($patchedPackages.Count))"
    }

    return @{
        IsFullyUpToDate              = $isFullyUpToDate
        NeedsPatchesUpdate           = $needsPatchesUpdate
        SourcesNeedingUpdate         = $sourcesNeedingUpdate
        NeedsMicroGUpdate            = $needsMicroGUpdate
        MissingPackages              = $missingPackages
        PackagesNeedingVersionUpdate = $packagesNeedingVersionUpdate
    }
}
catch {
    Write-Warning -Message "Failed to read repo metadata: $_"
    return $result
}
