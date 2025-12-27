<#
.SYNOPSIS
    Syncs the local repo to Bunny Storage.

.DESCRIPTION
    Uploads all files from the local repo directory to Bunny Storage.
    Only uploads files that have changed (based on file hash).
#>

param(
    [Parameter(Mandatory)]
    [string]$LocalRepoPath,

    [string]$RemotePrefix = ""
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot

# Get all files in local repo
$files = Get-ChildItem -Path $LocalRepoPath -File

Write-Output -InputObject "Syncing $($files.Count) file(s) to Bunny Storage..."

# Fetch remote file list for hash comparison
$remotePrefixPath = if ($RemotePrefix) { "$RemotePrefix/" } else { "" }
$remoteFilesUrl = "https://$env:BUNNY_STORAGE_ENDPOINT/$env:BUNNY_STORAGE_ZONE_NAME/$remotePrefixPath"
$headers = @{
    "AccessKey" = $env:BUNNY_STORAGE_ACCESS_KEY
}

$remoteFiles = @{}
try {
    $response = Invoke-RestMethod -Uri $remoteFilesUrl -Headers $headers -Method Get
    foreach ($item in @($response)) {
        if ($item.IsDirectory -eq $false -and $item.ObjectName) {
            # Bunny Storage returns Checksum as SHA256 HEX (uppercase usually)
            $remoteFiles[$item.ObjectName] = $item.Checksum
        }
    }
}
catch {
    Write-Warning -Message "Could not list remote files (might be empty): $_"
}

foreach ($file in $files) {
    $remotePath = "$remotePrefixPath$($file.Name)"
    $shouldUpload = $true

    # Calculate local hash
    $localHash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToUpper()

    # Check against remote
    if ($remoteFiles.ContainsKey($file.Name)) {
        $remoteHash = $remoteFiles[$file.Name]
        if ($remoteHash -eq $localHash) {
            Write-Output -InputObject "Skipping $($file.Name) (up to date)"
            $shouldUpload = $false
        }
        else {
            Write-Output -InputObject "Updating $($file.Name) (checksum mismatch)"
        }
    }
    else {
        Write-Output -InputObject "Uploading new file $($file.Name)"
    }

    if ($shouldUpload) {
        & "$ScriptRoot/Send-BunnyFile.ps1" `
            -LocalPath $file.FullName `
            -RemotePath $remotePath
    }
}

Write-Output -InputObject "Sync complete"
