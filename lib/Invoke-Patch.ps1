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

    [string]$PatchesVersion,  # Patches version for versionCode calculation

    [string]$OutputPath = "/tmp/friendly-journey",

    [string]$BinPath = "/tmp/friendly-journey/bin",

    [string]$LocalApkPath,  # Optional: path to check for manually downloaded APKs

    [string[]]$IncludePatches = @(),  # Patches to explicitly include

    [string[]]$ExcludePatches = @()   # Patches to exclude
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Helper function to extract versionCode from APK using aapt2
function Get-ApkVersionCode {
    param([string]$ApkPath)
    
    # Only works on actual .apk files, not xapk/apks/apkm
    if ($ApkPath -notmatch '\.apk$') {
        Write-Host -Object "Skipping versionCode extraction for non-APK file: $ApkPath"
        return $null
    }
    
    # Find aapt2 in Android SDK (pre-installed on GitHub runners)
    $androidHome = $env:ANDROID_HOME ?? "/usr/local/lib/android/sdk"
    $aapt2 = Get-ChildItem -Path "$androidHome/build-tools" -Filter "aapt2" -Recurse | 
    Sort-Object { $_.Directory.Name } -Descending | 
    Select-Object -First 1
    
    if (-not $aapt2) {
        Write-Warning -Message "aapt2 not found, cannot modify versionCode"
        return $null
    }
    
    try {
        $output = & $aapt2.FullName dump badging $ApkPath 2>&1 | Out-String
        if ($output -match "versionCode='(\d+)'") {
            $versionCode = [long]$Matches[1]
            Write-Host -Object "Extracted versionCode: $versionCode from $([System.IO.Path]::GetFileName($ApkPath))"
            return $versionCode
        }
        Write-Warning -Message "Could not extract versionCode from $ApkPath"
        return $null
    }
    catch {
        Write-Warning -Message "Error extracting versionCode: $_"
        return $null
    }
}

# Helper function to calculate patches build number from version string
function Get-PatchesBuildNumber {
    param([string]$Version)
    
    if (-not $Version) { return 0 }
    
    # Parse version like "4.26.0" -> 426 or "4.26.1" -> 4261
    $parts = $Version -split '\.'
    if ($parts.Count -ge 2) {
        # Use major * 100 + minor (* 10 if there's a patch version)
        $major = [int]$parts[0]
        $minor = [int]$parts[1]
        $patch = if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }
        return ($major * 100) + $minor + $patch
    }
    return 0
}

$workDir = Join-Path -Path $OutputPath -ChildPath "work-$PackageName"
New-Item -Path $workDir -ItemType Directory | Out-Null

try {
    $inputFiles = @()

    # Check for local APKs first
    if ($LocalApkPath -and (Test-Path -Path $LocalApkPath)) {
        Write-Host -Object "Checking for local APKs in $LocalApkPath..."
        $localPattern = if ($Version) { "$PackageName*$Version*" } else { "$PackageName*" }

        # Get all matching files (both split archives and regular APKs)
        $localMatches = Get-ChildItem -Path $LocalApkPath -Include "*.xapk", "*.apks", "*.apkm", "*.apk" -Recurse | 
        Where-Object { $_.Name -like $localPattern }

        if ($localMatches) {
            Write-Host -Object "Found $($localMatches.Count) local APK(s)"
            foreach ($match in $localMatches) {
                # Copy to work dir with unique name to avoid conflicts if names are similar (though they shouldn't be)
                $dest = Join-Path -Path $workDir -ChildPath $match.Name
                Copy-Item -Path $match.FullName -Destination $dest
                $inputFiles += $dest
            }
        }
    }

    if ($inputFiles.Count -eq 0) {
        # Fallback: Download specific architectures via apkeep
        Write-Host -Object "Downloading APKs for all architectures via apkeep..."
        $architectures = @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")

        foreach ($arch in $architectures) {
            Write-Host -Object "Downloading for architecture: $arch..."

            # Use a subfolder for each arch to avoid collision and easy identification
            $archWorkDir = Join-Path -Path $workDir -ChildPath $arch
            New-Item -Path $archWorkDir -ItemType Directory -Force | Out-Null

            $apkeepArgs = @(
                "--app", $(if ($Version) { "$PackageName@$Version" } else { $PackageName }),
                "--options", "arch=$arch",  # Specify arch
                $archWorkDir
            )

            # Run apkeep
            & "$BinPath/apkeep" @apkeepArgs | Out-Null

            # Find and move file
            $downloadedFile = Get-ChildItem -Path $archWorkDir -Include "*.apk", "*.xapk", "*.apks", "*.apkm" -Recurse | Select-Object -First 1

            if ($downloadedFile) {
                # Rename to include arch so unique in main workDir
                # (APKPure names usually don't include arch explicitly in a way we trust blindly, or duplicate names)
                # But actually, typically they do. Let's append arch just in case.

                $originalName = [System.IO.Path]::GetFileNameWithoutExtension($downloadedFile.Name)
                $extension = $downloadedFile.Extension
                $newName = "${originalName}-${arch}${extension}"
                $destPath = Join-Path -Path $workDir -ChildPath $newName

                Move-Item -Path $downloadedFile.FullName -Destination $destPath -Force
                $inputFiles += $destPath
                Write-Host -Object "Downloaded: $newName"
            }
            else {
                Write-Warning -Message "No APK found for architecture $arch"
            }
        }

        if ($inputFiles.Count -eq 0) {
            Write-Host -Object "Directory contents of ${workDir}:"
            Get-ChildItem -Path $workDir -Recurse | Out-Host
            throw "No APKs found after attempting download for architectures: $($architectures -join ', ')"
        }
    }

    $patchedApks = @()

    foreach ($inputFile in $inputFiles) {
        $inputFilename = [System.IO.Path]::GetFileNameWithoutExtension($inputFile)

        # Handle XAPK/APKS merging for LOCAL files if we have them in the list
        # (Note: simpler to just check extension here if we want to support local XAPK properly)
        if ($inputFile -match "\.(xapk|apks|apkm)$") {
            Write-Host -Object "Merging local split APK: $inputFilename..."
            $mergeDir = Join-Path -Path $workDir -ChildPath "merge-$inputFilename"
            unzip -q $inputFile -d $mergeDir | Out-Null

            $mergedInput = Join-Path -Path $workDir -ChildPath "$inputFilename-merged.apk"
            java -jar "$BinPath/APKEditor.jar" merge -i $mergeDir -o $mergedInput | Out-Null
            $inputFile = $mergedInput
            $inputFilename = "$inputFilename-merged"
        }

        # Patch
        Write-Host -Object "Patching $inputFilename..."
        $outputApk = Join-Path -Path $OutputPath -ChildPath "$PackageName-$inputFilename.apk"

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

        # Calculate and apply new versionCode if patches version is provided
        if ($PatchesVersion) {
            $originalVersionCode = Get-ApkVersionCode -ApkPath $inputFile
            if ($originalVersionCode) {
                $patchesBuildNumber = Get-PatchesBuildNumber -Version $PatchesVersion
                $newVersionCode = $originalVersionCode + $patchesBuildNumber
                Write-Host "Modifying versionCode: $originalVersionCode + $patchesBuildNumber = $newVersionCode"
                
                # Enable "Change version code" patch with calculated value
                $cliArgs += "-e"
                $cliArgs += "Change version code"
                $cliArgs += "-OversionCode=$newVersionCode"
            }
        }

        # Add enable/disable patches (using short options with separate value for reliable parsing)
        foreach ($patch in $IncludePatches) {
            $cliArgs += "-e"
            $cliArgs += $patch
        }
        foreach ($patch in $ExcludePatches) {
            $cliArgs += "-d"
            $cliArgs += $patch
        }

        $cliArgs += $inputFile

        java @cliArgs | Out-Null

        Write-Host -Object "Patched APK: $outputApk"
        $patchedApks += $outputApk
    }

    return $patchedApks
}
catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
finally {
    # Cleanup work directory
    Remove-Item -Path $workDir -Recurse -Force
}
