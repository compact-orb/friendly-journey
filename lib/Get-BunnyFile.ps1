<#
.SYNOPSIS
    Downloads a file from Bunny Storage.

.DESCRIPTION
    Downloads a single file from Bunny Storage using the Edge Storage API.
#>

param(
    [Parameter(Mandatory)]
    [string]$RemotePath,  # Path in storage zone, e.g., "entry.json"

    [Parameter(Mandatory)]
    [string]$LocalPath    # Local file path to save to
)

$ErrorActionPreference = "Stop"

$url = "https://$env:BUNNY_STORAGE_ENDPOINT/$env:BUNNY_STORAGE_ZONE_NAME/$RemotePath"

$headers = @{
    "AccessKey" = $env:BUNNY_STORAGE_ACCESS_KEY
}

Write-Output -InputObject "Downloading $RemotePath from Bunny Storage..."

try {
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
