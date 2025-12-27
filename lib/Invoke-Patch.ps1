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

# Helper function to extract metadata (versionCode, arch) from APK using aapt2
function Get-ApkMetadata {
    param([string]$ApkPath)

    $metadata = @{
        VersionCode  = $null
        Architecture = $null
    }

    # Only works on actual .apk files, not xapk/apks/apkm
    if ($ApkPath -notmatch '\.apk$') {
        Write-Host -Object "Skipping metadata extraction for non-APK file: $ApkPath"
        return $metadata
    }

    # Find aapt2 in Android SDK (pre-installed on GitHub runners)
    $androidHome = $env:ANDROID_HOME ?? "/usr/local/lib/android/sdk"
    $aapt2 = Get-ChildItem -Path "$androidHome/build-tools" -Filter "aapt2" -Recurse | 
    Sort-Object { $_.Directory.Name } -Descending | 
    Select-Object -First 1

    if (-not $aapt2) {
        Write-Warning -Message "aapt2 not found, cannot extract metadata"
        return $metadata
    }

    try {
        $output = & $aapt2.FullName dump badging $ApkPath 2>&1 | Out-String

        if ($output -match "versionCode='(\d+)'") {
            $metadata.VersionCode = [long]$Matches[1]
            Write-Host -Object "Extracted versionCode: $($metadata.VersionCode) from $([System.IO.Path]::GetFileName($ApkPath))"
        }

        # Extract native-code (architecture)
        if ($output -match "native-code: '([^']+)'") {
            # native-code line can look like: native-code: 'arm64-v8a' 'armeabi-v7a'
            # We take the first one as primary, or the one that matches our supported list
            $archs = $Matches[1] -split "'\s+'" | ForEach-Object { $_ -replace "'", "" }

            # Prefer arm64-v8a > armeabi-v7a > x86_64 > x86
            if ('arm64-v8a' -in $archs) { $metadata.Architecture = 'arm64-v8a' }
            elseif ('armeabi-v7a' -in $archs) { $metadata.Architecture = 'armeabi-v7a' }
            elseif ('x86_64' -in $archs) { $metadata.Architecture = 'x86_64' }
            elseif ('x86' -in $archs) { $metadata.Architecture = 'x86' }
            else { $metadata.Architecture = $archs[0] } # Fallback to first

            Write-Host -Object "Extracted architecture: $($metadata.Architecture)"
        }

        return $metadata
    }
    catch {
        Write-Warning -Message "Error extracting metadata: $_"
        return $metadata
    }
}

# Helper function to calculate patches build number from version string
function Get-PatchesBuildNumber {
    param([string]$Version)

    if (-not $Version) { return 0 }

    # Strip 'v' prefix if present and any suffix after hyphen (e.g., "v5.0.0-beta" -> "5.0.0")
    $cleanVersion = $Version -replace '^v', '' -replace '-.*$', ''

    # Parse version like "4.26.0" -> 426 or "4.26.1" -> 4261
    $parts = $cleanVersion -split '\.'
    if ($parts.Count -ge 2) {
        try {
            # Extract only numeric portions
            $major = [int]($parts[0] -replace '\D', '')
            $minor = [int]($parts[1] -replace '\D', '')
            $patch = if ($parts.Count -ge 3) { [int]($parts[2] -replace '\D', '') } else { 0 }
            $buildNumber = ($major * 100) + $minor + $patch
            Write-Host -Object "Patches build number: $Version -> $buildNumber"
            return $buildNumber
        }
        catch {
            Write-Warning -Message "Could not parse patches version '$Version': $_"
            return 0
        }
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

                $extension = $downloadedFile.Extension

                # Rename to strict format: PackageName-Arch.extension
                # This discards the original filename from the source to avoid duplication or garbage.
                $newName = "${PackageName}-${arch}${extension}"
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

        # Calculate patches build number and temporary version code (moved up for naming)
        $newVersionCodeCalculated = $null
        if ($PatchesVersion) {
            $originalVersionCode = Get-ApkVersionCode -ApkPath $inputFile
            if ($originalVersionCode) {
                $patchesBuildNumber = Get-PatchesBuildNumber -Version $PatchesVersion
                $newVersionCodeCalculated = $originalVersionCode + $patchesBuildNumber
            }
        }

        # Determine Architecture from input filename (if it matches our strict pattern or common patterns)
        $archSuffix = ""
        if ($inputFilename -match "(arm64-v8a|armeabi-v7a|x86_64|x86)") {
            $archSuffix = "-$($Matches[1])"
        }

        # Construct Output Filename
        # Format: PackageName[-VersionCode][-Arch].apk
        if ($newVersionCodeCalculated) {
            # If we have version code, use it.
            $outputName = "${PackageName}-${newVersionCodeCalculated}${archSuffix}.apk"
        }
        else {
            # Fallback to standard name without version code
            $outputName = "${PackageName}${archSuffix}.apk"

            # If input was merged, maybe append -merged?
            if ($inputFilename -match "-merged$") {
                $outputName = "${PackageName}${archSuffix}-merged.apk"
            }
        }

        $outputApk = Join-Path -Path $OutputPath -ChildPath $outputName

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
        if ($newVersionCodeCalculated) {
            Write-Host "Modifying versionCode: $originalVersionCode + $patchesBuildNumber = $newVersionCodeCalculated"
                
            # Enable "Change version code" patch with calculated value
            $cliArgs += "-e"
            $cliArgs += "Change version code"
            $cliArgs += "-OversionCode=$newVersionCodeCalculated"
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
