<#
.SYNOPSIS
    Downloads a file from Bunny Storage.

.DESCRIPTION
    Downloads a single file from Bunny Storage using the Edge Storage API.
#>

param(
    [Parameter(Mandatory)]
    [string]$RemotePath,  # Path in storage zone, e.g., "repo/entry.json"

    [Parameter(Mandatory)]
    [string]$LocalPath,   # Local file path to save to

    [Parameter(Mandatory)]
    [string]$AccessKey,

    [Parameter(Mandatory)]
    [string]$StorageZone,

    [Parameter(Mandatory)]
    [string]$Endpoint     # e.g., "la.storage.bunnycdn.com"
)

$ErrorActionPreference = "Stop"

$url = "https://$Endpoint/$StorageZone/$RemotePath"

$headers = @{
    "AccessKey" = $AccessKey
}

try {
    Write-Output -InputObject "Downloading $RemotePath from Bunny Storage..."
    Invoke-WebRequest -Uri $url -Headers $headers -OutFile $LocalPath
    Write-Output -InputObject "Downloaded to $LocalPath"
    return $true
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Output -InputObject "File not found: $RemotePath"
        return $false
    }
    throw
}
