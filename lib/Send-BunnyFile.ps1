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
    [string]$RemotePath  # Path in storage zone, e.g., "app.apk"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $LocalPath)) {
    throw "Local file not found: $LocalPath"
}

$url = "https://$env:BUNNY_STORAGE_ENDPOINT/$env:BUNNY_STORAGE_ZONE_NAME/$RemotePath"

$headers = @{
    "AccessKey"    = $env:BUNNY_STORAGE_ACCESS_KEY
    "Content-Type" = "application/octet-stream"
}

Write-Output -InputObject "Uploading $LocalPath to $RemotePath..."

# Read file as bytes
$fileBytes = [System.IO.File]::ReadAllBytes($LocalPath)

Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $fileBytes

Write-Output -InputObject "Uploaded successfully"
