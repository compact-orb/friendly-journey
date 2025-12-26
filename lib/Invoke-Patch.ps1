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

    [string]$KeystorePath,  # Optional: path to keystore for signing

    [string]$OutputPath = "/tmp/friendly-journey",

    [string]$BinPath = "/tmp/friendly-journey/bin"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$workDir = Join-Path -Path $OutputPath -ChildPath "work-$PackageName"
if (Test-Path -Path $workDir) {
    Remove-Item -Path $workDir -Recurse -Force
}
New-Item -Path $workDir -ItemType Directory | Out-Null

try {
    # Download APK
    Write-Output -InputObject "Downloading $PackageName..."
    $apkeepArgs = @("--app", $PackageName, "--options", "split_apk=true", $workDir)
    if ($Version) {
        $apkeepArgs = @("--app", "$PackageName@$Version", "--options", "split_apk=true", $workDir)
    }
    & "$BinPath/apkeep" @apkeepArgs | Out-Null

    # Find downloaded file (xapk or apk)
    $xapk = Get-ChildItem -Path $workDir -Filter "*.xapk" | Select-Object -First 1
    $apk = Get-ChildItem -Path $workDir -Filter "*.apk" | Select-Object -First 1

    if ($xapk) {
        # Merge split APK
        Write-Output -InputObject "Merging split APK..."
        $mergeDir = Join-Path -Path $workDir -ChildPath "merge"
        unzip -q $xapk.FullName -d $mergeDir | Out-Null

        $mergedApk = Join-Path -Path $workDir -ChildPath "merged.apk"
        java -jar "$BinPath/APKEditor.jar" merge -i $mergeDir -o $mergedApk | Out-Null
        $inputApk = $mergedApk
    }
    elseif ($apk) {
        $inputApk = $apk.FullName
    }
    else {
        throw "No APK or XAPK found for $PackageName"
    }

    # Patch
    Write-Output -InputObject "Patching $PackageName..."
    $outputApk = Join-Path -Path $OutputPath -ChildPath "$PackageName.apk"

    # Build revanced-cli arguments
    $cliArgs = @(
        "-jar", "$BinPath/revanced-cli.jar",
        "patch",
        "--patches=$PatchesPath",
        "--out=$outputApk"
    )

    # Add keystore if provided
    if ($KeystorePath -and (Test-Path $KeystorePath)) {
        $cliArgs += "--keystore=$KeystorePath"
    }

    $cliArgs += $inputApk

    java @cliArgs | Out-Null

    Write-Output -InputObject "Patched APK: $outputApk"
    return $outputApk
}
finally {
    # Cleanup work directory
    if (Test-Path -Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force
    }
}
