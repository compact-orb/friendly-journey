<#
.SYNOPSIS
    Downloads existing APKs from Bunny Storage to the local repo.

.DESCRIPTION
    Lists all files in the remote fdroid/repo directory.
    Downloads any .apk files that miss in the local repo directory.
    This prevents F-Droid from deleting existing apps when only adding new ones.
#>

param(
    [Parameter(Mandatory)]
    [string]$LocalRepoPath,

    [string]$RemotePrefix = "fdroid/repo"
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot

# Ensure local repo exists
if (-not (Test-Path -Path $LocalRepoPath)) {
    New-Item -Path $LocalRepoPath -ItemType Directory | Out-Null
}

Write-Host -Object "Checking for existing APKs in Bunny Storage..."

# Fetch remote file list
$remoteFilesUrl = "https://$env:BUNNY_STORAGE_ENDPOINT/$env:BUNNY_STORAGE_ZONE_NAME/$RemotePrefix/"
$headers = @{
    "AccessKey" = $env:BUNNY_STORAGE_ACCESS_KEY
}

try {
    $response = Invoke-RestMethod -Uri $remoteFilesUrl -Headers $headers -Method Get

    # Filter for APK files
    $remoteApks = @($response) | Where-Object { 
        $_.IsDirectory -eq $false -and $_.ObjectName.EndsWith(".apk") 
    }

    Write-Host -Object "Found $($remoteApks.Count) APK(s) in remote storage."

    foreach ($apk in $remoteApks) {
        $localPath = Join-Path -Path $LocalRepoPath -ChildPath $apk.ObjectName

        if (-not (Test-Path -Path $localPath)) {
            Write-Host -Object "Restoring $($apk.ObjectName)..."

            & "$ScriptRoot/Get-BunnyFile.ps1" `
                -RemotePath "$RemotePrefix/$($apk.ObjectName)" `
                -LocalPath $localPath
        }
        else {
            Write-Host -Object "Skipping $($apk.ObjectName) (exists locally)"
        }
    }
}
catch {
    Write-Warning -Message "Could not list remote files: $_"
}
