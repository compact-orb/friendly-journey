<#
.SYNOPSIS
    Updates the F-Droid repository with patched APKs.

.DESCRIPTION
    Generates index-v1.json and optionally signs it to index-v1.jar.
    Stores patches version in entry.json for version checking.
#>

param(
    [Parameter(Mandatory)]
    [string]$RepoPath,

    [Parameter(Mandatory)]
    [string]$PatchesVersion,

    [string]$KeystorePath,  # Optional: keystore for signing

    [string]$KeyAlias = "repo",

    [string]$RepoName = "ReVanced Apps",

    [string]$RepoDescription = "ReVanced patched apps"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Ensure repo directory exists
if (-not (Test-Path -Path $RepoPath)) {
    New-Item -Path $RepoPath -ItemType Directory -Force | Out-Null
}

# Get all APKs in repo
$apkFiles = Get-ChildItem -Path $RepoPath -Filter "*.apk"

# Build app list
$apps = @{}
$packages = @{}

foreach ($apk in $apkFiles) {
    # Extract basic info from filename (package.apk)
    $packageName = [System.IO.Path]::GetFileNameWithoutExtension($apk.Name)

    $appInfo = @{
        packageName          = $packageName
        suggestedVersionCode = 1
        suggestedVersionName = $PatchesVersion
        name                 = $packageName
        summary              = "ReVanced patched $packageName"
        description          = "Patched with ReVanced patches $PatchesVersion"
        license              = "Unknown"
        icon                 = ""
    }

    $apps[$packageName] = $appInfo

    # Package info
    $apkHash = (Get-FileHash -Path $apk.FullName -Algorithm SHA256).Hash.ToLower()
    $apkSize = $apk.Length

    $packages[$packageName] = @(
        @{
            versionCode = 1
            versionName = $PatchesVersion
            hash        = $apkHash
            hashType    = "sha256"
            size        = $apkSize
            apkName     = $apk.Name
            added       = [int](Get-Date -UFormat %s)
        }
    )
}

# Build index
$index = @{
    repo     = @{
        name        = $RepoName
        description = $RepoDescription
        timestamp   = [int](Get-Date -UFormat %s) * 1000
        version     = 21
    }
    apps     = $apps.Values
    packages = $packages
}

# Write index-v1.json
$indexPath = Join-Path -Path $RepoPath -ChildPath "index-v1.json"
$index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexPath
Write-Output -InputObject "Generated $indexPath"

# Sign index to JAR if keystore provided
if ($KeystorePath -and (Test-Path $KeystorePath)) {
    Write-Output -InputObject "Signing index with keystore..."
    $jarPath = Join-Path -Path $RepoPath -ChildPath "index-v1.jar"

    # Create temporary directory for JAR contents
    $jarTempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "fdroid-jar-$(Get-Random)"
    New-Item -Path $jarTempDir -ItemType Directory | Out-Null

    # Download Bouncy Castle provider if needed
    # Fetch latest version
    try {
        $response = Invoke-RestMethod -Uri "https://search.maven.org/solrsearch/select?q=g:org.bouncycastle+AND+a:bcprov-jdk18on&rows=1&wt=json"
        $bcVersion = $response.response.docs[0].latestVersion
        Write-Output -InputObject "Latest Bouncy Castle version: $bcVersion"
    }
    catch {
        Write-Warning -Message "Failed to fetch latest Bouncy Castle version, falling back to 1.78.1"
        $bcVersion = "1.78.1"
    }

    $bcJar = "bcprov-jdk18on-$bcVersion.jar"
    $bcUrl = "https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/$bcVersion/$bcJar"
    $bcPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $bcJar

    if (-not (Test-Path -Path $bcPath)) {
        Write-Output -InputObject "Downloading Bouncy Castle provider..."
        Invoke-WebRequest -Uri $bcUrl -OutFile $bcPath
    }

    try {
        Copy-Item -Path $indexPath -Destination $jarTempDir

        # Create unsigned JAR
        $unsignedJar = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "unsigned-$(Get-Random).jar"
        Push-Location $jarTempDir
        jar -cf $unsignedJar "index-v1.json" 2>&1 | Out-Null
        Pop-Location

        # Sign with jarsigner using BKS provider (password-less)
        & jarsigner -keystore $KeystorePath `
            -storetype "BKS" `
            -providerpath $bcPath `
            -provider "org.bouncycastle.jce.provider.BouncyCastleProvider" `
            -protected `
            -signedjar $jarPath `
            $unsignedJar `
            $KeyAlias 2>&1 | Out-Null

        Remove-Item -Path $unsignedJar -Force -ErrorAction SilentlyContinue
        Write-Output -InputObject "Signed $jarPath"
    }
    finally {
        Start-Sleep -Milliseconds 500  # Allow file handles to close
        Remove-Item -Path $jarTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Output -InputObject "No keystore provided, skipping JAR signing"
}

# Write entry.json with patches version for version checking
$entryPath = Join-Path -Path $RepoPath -ChildPath "entry.json"
$entry = @{
    patchesVersion = $PatchesVersion
    timestamp      = (Get-Date -Format "o")
    repoName       = $RepoName
}
$entry | ConvertTo-Json | Set-Content -Path $entryPath
Write-Output -InputObject "Updated $entryPath"

Write-Output -InputObject "F-Droid repo updated successfully"
