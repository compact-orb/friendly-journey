<#
.SYNOPSIS
    Uploads a file to Bunny Storage.

.DESCRIPTION
    Uploads a single file to Bunny Storage using the Edge Storage API.
#>

param(
    [Parameter(Mandatory)]
    [string]$LocalPath,   # Local file path to upload

    [Parameter(Mandatory)]
    [string]$RemotePath,  # Path in storage zone, e.g., "repo/app.apk"

    [Parameter(Mandatory)]
    [string]$AccessKey,

    [Parameter(Mandatory)]
    [string]$StorageZone,

    [Parameter(Mandatory)]
    [string]$Endpoint     # e.g., "la.storage.bunnycdn.com"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $LocalPath)) {
    throw "Local file not found: $LocalPath"
}

$url = "https://$Endpoint/$StorageZone/$RemotePath"

$headers = @{
    "AccessKey"    = $AccessKey
    "Content-Type" = "application/octet-stream"
}

Write-Output -InputObject "Uploading $LocalPath to $RemotePath..."

# Read file as bytes
$fileBytes = [System.IO.File]::ReadAllBytes($LocalPath)

Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $fileBytes

Write-Output -InputObject "Uploaded successfully"
