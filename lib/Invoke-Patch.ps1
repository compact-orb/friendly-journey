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

    [string[]]$IncludePatches = @(),  # Patches to explicitly include

    [string[]]$ExcludePatches = @()   # Patches to exclude
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$workDir = Join-Path -Path $OutputPath -ChildPath "work-$PackageName"
New-Item -Path $workDir -ItemType Directory | Out-Null

try {
    # Download APK
    Write-Host -Object "Downloading $PackageName..."
    if ($Version) {
        $apkeepArgs = @("--app", "$PackageName@$Version", "--options", "split_apk=true", $workDir)
    }
    else {
        $apkeepArgs = @("--app", $PackageName, "--options", "split_apk=true", $workDir)
    }
    & "$BinPath/apkeep" @apkeepArgs | Out-Null

    # Find downloaded file (xapk or apk)
    $xapk = Get-ChildItem -Path $workDir -Filter "*.xapk" | Select-Object -First 1
    $apk = Get-ChildItem -Path $workDir -Filter "*.apk" | Select-Object -First 1

    if ($xapk) {
        # Merge split APK from xapk
        Write-Host -Object "Merging split APK..."
        $mergeDir = Join-Path -Path $workDir -ChildPath "merge"
        unzip -q $xapk.FullName -d $mergeDir | Out-Null

        $mergedApk = Join-Path -Path $workDir -ChildPath "merged.apk"
        java -jar "$BinPath/APKEditor.jar" merge -i $mergeDir -o $mergedApk | Out-Null
        $inputApk = $mergedApk
    }
    elseif ($apk) {
        # Use the regular APK directly
        Write-Host -Object "Using downloaded APK directly..."
        $inputApk = $apk.FullName
    }
    else {
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
