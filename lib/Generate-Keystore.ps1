<#
.SYNOPSIS
    Generates a ReVanced-compatible BKS keystore using a Podman container.

.DESCRIPTION
    This script runs a temporary Podman container (eclipse-temurin:21-jdk) to generate a
    password-less BKS keystore using the Bouncy Castle provider.
    This is required for ReVanced CLI to work without explicit password inputs.

.PARAMETER OutputPath
    The path where the keystore will be saved. Default: ./manual.keystore

.PARAMETER Alias
    The alias for the key entry. Default: release

.PARAMETER CN
    The Common Name for the certificate. Default: ReVanced

.EXAMPLE
    ./Generate-Keystore.ps1 -OutputPath "./my.keystore" -Alias "myalias"
#>

param(
    [string]$OutputPath = "$PWD/manual.keystore",
    [string]$Alias = "release",
    [string]$CN = "ReVanced"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$OutputPath = Resolve-Path -Path $OutputPath -ErrorAction SilentlyContinue
if (-not $OutputPath) {
    # If path doesn't exist (creating new file), resolve the parent and append filename
    $parent = Split-Path -Parent $OutputPath
    if (-not $parent) { $parent = "." }
    $parent = Resolve-Path -Path $parent
    $fileName = Split-Path -Leaf $OutputPath
    $OutputPath = Join-Path -Path $parent -ChildPath $fileName
}

Write-Host -Object "Generating keystore at: $OutputPath"
Write-Host -Object "Alias: $Alias"
Write-Host -Object "Common Name: $CN"



# Container details
$image = "docker.io/library/eclipse-temurin:21-jdk"

$containerWorkDir = "/workspace"

# The command to run inside the container
# 1. Fetch latest version from Maven Central
# 2. Download it
$bashCommand = @"
set -e
echo 'Fetching latest Bouncy Castle version...'
LATEST_VERSION=\$(curl -s "https://search.maven.org/solrsearch/select?q=g:org.bouncycastle+AND+a:bcprov-jdk18on&rows=1&wt=json" | grep -o '"latestVersion":"[^"]*"' | cut -d'"' -f4)
echo "Latest version is: \$LATEST_VERSION"

BC_JAR="bcprov-jdk18on-\$LATEST_VERSION.jar"
BC_URL="https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/\$LATEST_VERSION/\$BC_JAR"

echo "Downloading \$BC_JAR..."
curl -s -L -o "\$BC_JAR" "\$BC_URL"

echo 'Generating Keystore...'
keytool -genkeypair \
    -alias "$Alias" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -keystore "output.keystore" \
    -protected \
    -storetype BKS \
    -providerpath "\$BC_JAR" \
    -provider org.bouncycastle.jce.provider.BouncyCastleProvider \
    -dname "CN=$CN, OU=ReVanced, O=ReVanced, L=Unknown, ST=Unknown, C=Unknown"

echo 'Done.'
"@

# Run Podman
# We mount the parent directory of OutputPath to /host in the container to copy the result back
$outputDir = Split-Path -Parent $OutputPath
$outputFilename = Split-Path -Leaf $OutputPath

if (-not $outputDir) { $outputDir = $PWD }

Write-Host -Object "Starting Podman container..."

podman run --rm `
    -v "$outputDir`:/host" `
    -w $containerWorkDir `
    $image `
    bash -c "$bashCommand && cp output.keystore /host/$outputFilename"

Write-Host -Object "Successfully generated keystore: $OutputPath"
