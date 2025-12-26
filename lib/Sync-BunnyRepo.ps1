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

    [string]$RemoteBasePath = "repo",

    [Parameter(Mandatory)]
    [string]$AccessKey,

    [Parameter(Mandatory)]
    [string]$StorageZone,

    [Parameter(Mandatory)]
    [string]$Endpoint
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot

# Get all files in local repo
$files = Get-ChildItem -Path $LocalRepoPath -File

Write-Output -InputObject "Syncing $($files.Count) file(s) to Bunny Storage..."

foreach ($file in $files) {
    $remotePath = "$RemoteBasePath/$($file.Name)"

    & "$ScriptRoot/Send-BunnyFile.ps1" `
        -LocalPath $file.FullName `
        -RemotePath $remotePath `
        -AccessKey $AccessKey `
        -StorageZone $StorageZone `
        -Endpoint $Endpoint
}

Write-Output -InputObject "Sync complete"
