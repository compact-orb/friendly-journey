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
|`FDROID_REPO_URL`|F-Droid repository URL|
|`GOOGLE_PLAY_EMAIL`|Gmail address for Google Play downloads|
|`GOOGLE_PLAY_AAS_TOKEN`|AAS token for Google Play API access|

### Google Play AAS Token

APKs are downloaded directly from Google Play. This requires a one-time setup to obtain an AAS token:

1. Visit the [Google Embedded Setup page](https://accounts.google.com/EmbeddedSetup)
2. Open browser DevTools → Network tab
3. Log in with your Google account
4. Find the last request to `accounts.google.com` and check its Cookies
5. Copy the `oauth_token` value (starts with `oauth2_4/`)
6. Run apkeep to exchange for an AAS token:

   ```bash
   apkeep -e 'your@gmail.com' --oauth-token 'oauth2_4/...'
   ```

7. Save the printed AAS token as `GOOGLE_PLAY_AAS_TOKEN` secret
8. Save your email as `GOOGLE_PLAY_EMAIL` secret

> **Note**: The OAuth token is single-use, but the AAS token can be reused indefinitely.

### Creating Keystores

You need two keystores:

1. **APK Keystore (BKS)**: For signing the patched APKs with ReVanced CLI. Uses password-less BKS format.
2. **Repo Keystore (JKS)**: For signing the F-Droid repository index with fdroidserver. Uses JKS with password `password`.

#### APK Keystore (BKS, password-less)

```bash
podman run --rm --volume "$PWD:/work" --workdir /work docker.io/library/eclipse-temurin:21-jdk bash -c '
  curl --silent --location --output bcprov.jar https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/1.80/bcprov-jdk18on-1.80.jar && \
  keytool -genkeypair \
    -alias release \
    -keyalg EC \
    -groupname secp256r1 \
    -validity 10000 \
    -keystore apk.keystore \
    -protected \
    -storetype BKS \
    -providerpath bcprov.jar \
    -provider org.bouncycastle.jce.provider.BouncyCastleProvider \
    -dname "CN=ReVanced"
  rm bcprov.jar'
```

#### Repo Keystore (JKS, password: `password`)

```bash
podman run --rm --volume "$PWD:/work" --workdir /work docker.io/library/eclipse-temurin:21-jdk \
  keytool -genkeypair \
    -alias release \
    -keyalg EC \
    -groupname secp256r1 \
    -validity 10000 \
    -keystore repo.keystore \
    -storepass password \
    -keypass password \
    -dname "CN=ReVanced"
```

#### Encoding for Environment Variables

Once generated, encode them to Base64 for GitHub Secrets (`APK_KEYSTORE_BASE64`, `REPO_KEYSTORE_BASE64`):

```bash
base64 --wrap=0 apk.keystore
base64 --wrap=0 repo.keystore
```

## F-Droid Repository

To add the repository to F-Droid:

1. Open F-Droid app
2. Go to **Settings** → **Repositories**
3. Tap **+** and enter the repository URL
4. Enable the repository and refresh

The repository URL is your Bunny Storage CDN URL (e.g., `https://your-cdn.b-cdn.net`).

## Requirements

- PowerShell 7+
- Java 17+
- Docker or Podman (for fdroidserver)
- Internet connection for downloading tools and APKs
