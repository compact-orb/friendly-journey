<#
.SYNOPSIS
    Patches an Android app with ReVanced.

.DESCRIPTION
    Downloads an app via apkeep, merges split APK if needed, and patches with revanced-cli.
    If no keystore is provided, revanced-cli will auto-generate one.
#>

param(
    [Parameter(Mandatory)]
    [string]$PackageName,

    [string]$Version,  # Optional: specific version to download

    [Parameter(Mandatory)]
    [string]$PatchesPath,  # Path to .rvp file

    [Parameter(Mandatory)]
    [string]$KeystorePath,  # Path to keystore for signing

    [string]$OutputPath = "/tmp/friendly-journey",

    [string]$BinPath = "/tmp/friendly-journey/bin",

    [string]$LocalApkPath,  # Optional: path to check for manually downloaded APKs

    [string[]]$IncludePatches = @(),  # Patches to explicitly include

    [string[]]$ExcludePatches = @()   # Patches to exclude
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$workDir = Join-Path -Path $OutputPath -ChildPath "work-$PackageName"
New-Item -Path $workDir -ItemType Directory | Out-Null

try {
    $downloaded = $false

    # Check for local APK first
    if ($LocalApkPath -and (Test-Path -Path $LocalApkPath)) {
        Write-Host -Object "Checking for local APK in $LocalApkPath..."
        $localPattern = if ($Version) { "$PackageName*$Version*" } else { "$PackageName*" }

        # Check for XAPK/APKS/APKM
        $localSplit = Get-ChildItem -Path $LocalApkPath -Include "*.xapk", "*.apks", "*.apkm" -Recurse | 
        Where-Object { $_.Name -like $localPattern } | Select-Object -First 1

        # Check for regular APK
        $localApk = Get-ChildItem -Path $LocalApkPath -Filter "*.apk" -Recurse | 
        Where-Object { $_.Name -like $localPattern } | Select-Object -First 1

        if ($localSplit) {
            Write-Host -Object "Found local split APK: $($localSplit.Name)"
            Copy-Item -Path $localSplit.FullName -Destination $workDir
            $downloaded = $true
        }
        elseif ($localApk) {
            Write-Host -Object "Found local APK: $($localApk.Name)"
            Copy-Item -Path $localApk.FullName -Destination $workDir
            $downloaded = $true
        }
    }

    if (-not $downloaded) {
        # Download APK via apkeep (default source: apk-pure)
        Write-Host -Object "Downloading $PackageName..."
        $apkeepArgs = @(
            "--app", $(if ($Version) { "$PackageName@$Version" } else { $PackageName }),
            $workDir
        )
        & "$BinPath/apkeep" @apkeepArgs | Out-Null
    }

    # Find downloaded file - check multiple formats:
    # 1. Split APK archives (xapk, apks, apkm)
    # 2. Regular single APK file
    $splitApk = Get-ChildItem -Path $workDir -Include "*.xapk", "*.apks", "*.apkm" -Recurse | Select-Object -First 1
    $apk = Get-ChildItem -Path $workDir -Filter "*.apk" | Select-Object -First 1

    if ($splitApk) {
        # Merge split APK from split package archive
        Write-Host -Object "Found split APK archive: $($splitApk.Name), merging..."
        $mergeDir = Join-Path -Path $workDir -ChildPath "merge"
        unzip -q $splitApk.FullName -d $mergeDir | Out-Null

        $mergedApk = Join-Path -Path $workDir -ChildPath "merged.apk"
        java -jar "$BinPath/APKEditor.jar" merge -i $mergeDir -o $mergedApk | Out-Null
        $inputApk = $mergedApk
    }
    elseif ($apk) {
        # Use the regular APK directly
        Write-Host -Object "Using downloaded APK directly: $($apk.Name)"
        $inputApk = $apk.FullName
    }
    else {
        Write-Host -Object "Directory contents of ${workDir}:"
        Get-ChildItem -Path $workDir -Recurse | Out-Host
        throw "No APK or XAPK file found in $workDir after download"
    }

    # Patch
    Write-Host -Object "Patching $PackageName..."
    $outputApk = Join-Path -Path $OutputPath -ChildPath "$PackageName.apk"

    # Build revanced-cli arguments
    $cliArgs = @(
        "-jar", "$BinPath/revanced-cli.jar",
        "patch",
        "--patches=$PatchesPath",
        "--out=$outputApk"
    )

    # Add keystore if provided (alias must match what was used during keystore generation)
    $cliArgs += "--keystore=$KeystorePath"
    $cliArgs += "--keystore-entry-alias=release"

    # Add enable/disable patches (using short options with separate value for reliable parsing)
    foreach ($patch in $IncludePatches) {
        $cliArgs += "-e"
        $cliArgs += $patch
    }
    foreach ($patch in $ExcludePatches) {
        $cliArgs += "-d"
        $cliArgs += $patch
    }

    $cliArgs += $inputApk

    java @cliArgs | Out-Null

    Write-Host -Object "Patched APK: $outputApk"
    return $outputApk
}
catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
finally {
    # Cleanup work directory
    Remove-Item -Path $workDir -Recurse -Force
}
