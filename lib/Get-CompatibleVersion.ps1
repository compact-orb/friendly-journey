<#
.SYNOPSIS
    Finds the latest compatible app version from revanced-patches source.

.DESCRIPTION
    Parses the revanced-patches source code to find compatible versions
    for a specific app. Returns the latest version that works with all patches.
#>

param(
    [Parameter(Mandatory)]
    [string]$SourceZipPath,

    [Parameter(Mandatory)]
    [string]$PatchesPath,  # e.g., "youtube", "music"

    [Parameter(Mandatory)]
    [string]$PackageName   # e.g., "com.google.android.youtube"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$extractPath = "/tmp/friendly-journey/revanced-source"

# Clean and extract
if (Test-Path -Path $extractPath) {
    Remove-Item -Path $extractPath -Recurse -Force
}
New-Item -Path $extractPath -ItemType Directory | Out-Null
unzip -q $SourceZipPath -d $extractPath

# Find the patches directory
$targetDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
$patchesDir = Join-Path -Path $targetDir.FullName -ChildPath "patches/src/main/kotlin/app/revanced/patches/$PatchesPath"

if (-not (Test-Path -Path $patchesDir)) {
    Write-Warning -Message "Patches directory not found: $patchesDir"
    Remove-Item -Path $extractPath -Recurse -Force
    return $null
}

$ktFiles = Get-ChildItem -Path $patchesDir -Filter "*.kt" -Recurse
$allVersions = @()

foreach ($file in $ktFiles) {
    $content = Get-Content -Path $file.FullName -Raw

    # Match compatibleWith block for the target package
    if ($content -match "compatibleWith\s*\(\s*`"$PackageName`"\s*\(([\s\S]*?)\)\s*\)") {
        $versionBlock = $matches[1]
        $versions = [regex]::Matches($versionBlock, '"(\d+\.\d+\.\d+)"') | ForEach-Object -Process { $_.Groups[1].Value }

        if ($versions.Count -gt 0) {
            $allVersions += , $versions
        }
    }
}

# Cleanup
Remove-Item -Path $extractPath -Recurse -Force

if ($allVersions.Count -eq 0) {
    Write-Output -InputObject "No version constraints found, using latest"
    return $null
}

# Find common versions across all patches
$commonVersions = $allVersions[0]
for ($i = 1; $i -lt $allVersions.Count; $i++) {
    $commonVersions = $commonVersions | Where-Object { $allVersions[$i] -contains $_ }
}

if ($commonVersions.Count -eq 0) {
    Write-Warning -Message "No common compatible versions found"
    return $null
}

# Return the latest compatible version
$latestVersion = $commonVersions | Sort-Object { [Version]$_ } -Descending | Select-Object -First 1
Write-Output -InputObject "Latest compatible version for ${PackageName}: $latestVersion"
return "$latestVersion"
