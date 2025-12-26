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

```bash
# APK signing keystore
keytool -genkey -v -keystore apk.keystore -alias key -keyalg EC -groupname secp256r1 -validity 10000

# Repo signing keystore
keytool -genkey -v -keystore repo.keystore -alias key -keyalg EC -groupname secp256r1 -validity 10000

# Encode for GitHub secrets
base64 -w 0 apk.keystore
base64 -w 0 repo.keystore
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
