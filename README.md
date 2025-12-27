# friendly-journey

[![CodeFactor](https://www.codefactor.io/repository/github/compact-orb/friendly-journey/badge)](https://www.codefactor.io/repository/github/compact-orb/friendly-journey)

Automated ReVanced patching pipeline with F-Droid repository hosting.

## About

friendly-journey patches Android apps using [ReVanced](https://revanced.app) and publishes them to a self-hosted F-Droid repository. It supports automatic updates and syncs to Bunny Storage for CDN distribution.

## Features

- GitHub Actions workflow for automation
- Automatic patching using ReVanced CLI
- F-Droid repository generation
- Bunny Storage sync for CDN hosting
- Keystore management via environment variables

### Configuration

Define apps to patch in `apps.yaml`:

```yaml
apps:
  - name: "YouTube"
    package: "com.google.android.youtube"
    include:
      - "Change header"
    exclude:
      - "Change header"
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

### Manual APK Upload (Optional)

If a specific app version is not available on APKPure or you want to provide your own APKs, place them in the `downloads` directory in the repository root.

- Naming convention: `PackageName[-Version]-Arch.apk`
- Examples:
  - `com.google.android.youtube-arm64-v8a.apk`
  - `com.google.android.youtube-19.16.39-arm64-v8a.apk`
- **Supported Architectures**: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- **Important**: The filename *must* contain one of the supported architecture strings for the script to correctly identify it. If you have a universal APK, you may need to manually rename it to include an architecture or modify the script to handle it.

The script will check this directory before attempting to download from apkeep.

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

> [!NOTE]
> **Security**: The repo keystore uses a known password (`password`) and the APK keystore is password-less. This is acceptable here because the keystores themselves are stored as GitHub Secrets, which are encrypted at rest and only exposed during workflow execution. The security boundary is GitHub's secret management rather than the keystore passwords.

## F-Droid Repository

To add the repository to F-Droid:

1. Open F-Droid app
2. Go to **Settings** → **Repositories**
3. Tap **+** and enter the repository URL
4. Enable the repository and refresh

The repository URL is your Bunny Storage CDN URL (e.g., `https://your-cdn.b-cdn.net/fdroid/repo`).
