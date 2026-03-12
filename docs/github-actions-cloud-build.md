# GitHub Actions Cloud Build

This repository can build Android APKs and Windows installers in GitHub Actions.

To keep the repository pushable to GitHub, generated installers under `releases/` and oversized optional TTS model assets are not tracked in Git. Cloud builds produce installers as workflow artifacts instead.

## Workflows

- `.github/workflows/android-release.yml`
  - Runs on `ubuntu-latest`
  - Builds `app-release.apk`
  - Uploads the APK as a workflow artifact
- `.github/workflows/windows-release.yml`
  - Runs on `windows-latest`
  - Builds the Flutter Windows release bundle
  - Packages an installable `.exe` with Inno Setup
  - Uploads both the installer and the portable `dist` folder as workflow artifacts

## Required GitHub Secrets

Only the Android workflow needs secrets.

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

PowerShell command to generate `ANDROID_KEYSTORE_BASE64` from the local keystore:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".keys\release.jks"))
```

If `gh` is installed and authenticated, you can set all four Android secrets with one command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/set_github_android_secrets.ps1 `
  -Repo yuelangmanle/wenwenTome `
  -StorePassword "<store-password>" `
  -KeyPassword "<key-password>" `
  -KeyAlias "<key-alias>"
```

## Handoff Checklist

If this project is handed to another person, they need these items to keep cloud builds working:

- Repository write access on `yuelangmanle/wenwenTome`
- GitHub Actions access
- The Android signing keystore: `.keys/release.jks`
- The Android signing values:
  - `storePassword`
  - `keyPassword`
  - `keyAlias`
- GitHub CLI access if they want to manage workflows and secrets from the terminal

Recommended handoff steps:

1. Give the new maintainer repository admin or Actions access.
2. Transfer `.keys/release.jks` through a secure channel. Do not commit it.
3. Transfer the three signing values through a secure channel or password manager.
4. Have the maintainer run `gh auth login`.
5. Have the maintainer run `scripts/set_github_android_secrets.ps1` to refresh repository secrets.
6. Trigger `android-release` and `windows-release` once from GitHub Actions to verify the setup.

If the repository moves to a different GitHub repo, the secrets must be created again in the new repository.

## Triggering Builds

- Push to `master`
- Push a tag like `v2.6.11`
- Run either workflow manually from the GitHub Actions page

## Downloading Outputs

After a workflow finishes, open the run in GitHub Actions and download:

- `wenwen_tome-android-release`
- `wenwen_tome-windows-installer`
- `wenwen_tome-windows-dist`

## Notes

- The Windows installer is currently unsigned. It is installable, but Windows SmartScreen may still warn users.
- If code signing is needed later, add a certificate-based signing step before uploading the installer artifact.
- Losing the Android keystore or its passwords means future APK updates cannot reliably replace earlier signed releases.
- Optional large TTS voice packs are expected to be downloaded at runtime or restored locally outside Git.
