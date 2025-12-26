# friendly-journey

Automated ReVanced patching pipeline with F-Droid repository hosting.

## About

friendly-journey patches Android apps using [ReVanced](https://revanced.app) and publishes them to a self-hosted F-Droid repository. It supports automatic updates and syncs to Bunny Storage for CDN distribution.

## Features

- Automatic patching using ReVanced CLI
- F-Droid repository generation
- Bunny Storage sync for CDN hosting
- GitHub Actions workflow for automation
- Keystore management via environment variables

## Usage

```powershell
./FriendlyJourney.ps1 [-ConfigPath <path>] [-RepoPath <path>]
```

### Configuration

Define apps to patch in `apps.yaml`:

```yaml
apps:
  - name: "YouTube"
    package: "com.google.android.youtube"
    patches_path: "app/revanced/patches/youtube"
```

### Environment Variables

|Variable|Description|
|----------|-------------|
|`APK_KEYSTORE_BASE64`|Base64-encoded APK signing keystore|
|`REPO_KEYSTORE_BASE64`|Base64-encoded repo signing keystore|
|`BUNNY_STORAGE_ACCESS_KEY`|Bunny Storage API key|
|`BUNNY_STORAGE_ZONE_NAME`|Bunny Storage zone name|
|`BUNNY_STORAGE_ENDPOINT`|Bunny Storage endpoint URL|

### Creating Keystores

You need two keystores:

1. **APK Keystore**: For signing the patched APKs (ReVanced).
2. **Repo Keystore**: For signing the F-Droid repository index.

Both can be generated using the BKS format (password-less) for seamless automation.

#### Using Podman manually

Run this command twice, allowing you to generate both the APK and Repo keystores.
*Change the alias and output filename as needed.*

```bash
# Generate a BKS keystore using Eclipse Temurin (Java 21) and Bouncy Castle
podman run --rm --volume "$PWD:/work" --workdir /work docker.io/library/eclipse-temurin:21-jdk bash -c '
  curl --silent --location --output bcprov.jar https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/1.80/bcprov-jdk18on-1.80.jar && \
  keytool -genkeypair \
    --alias release \
    --keyalg EC \
    --groupname secp256r1 \
    --validity 10000 \
    --keystore output.keystore \
    --protected \
    --storetype BKS \
    --providerpath bcprov.jar \
    --provider org.bouncycastle.jce.provider.BouncyCastleProvider \
    --dname "CN=ReVanced"
  rm bcprov.jar'
```

#### Encoding for Environment Variables

Once generated, encode them to Base64 to set as GitHub Secrets or environment variables (`APK_KEYSTORE_BASE64`, `REPO_KEYSTORE_BASE64`).

```bash
base64 --wrap=0 ApkKeystore.keystore
base64 --wrap=0 RepoKeystore.keystore
```

## F-Droid Repository

To add the repository to F-Droid:

1. Open F-Droid app
2. Go to **Settings** → **Repositories**
3. Tap **+** and enter the repository URL
4. Enable the repository and refresh

The repository URL is your Bunny Storage CDN URL with `/repo` appended (e.g., `https://your-cdn.b-cdn.net/repo`).

## Requirements

- PowerShell 7+
- Java 17+
- Internet connection for downloading tools and APKs
