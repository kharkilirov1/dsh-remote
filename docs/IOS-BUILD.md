# Building and installing the iOS app without a Mac

DSH Remote (`dsh-mobile-app`) is a Flutter client that remote-controls DeepSeek Harness on your PC. Upstream ships Android only; this repository adds the iOS target and builds it **without owning a Mac**:

1. a GitHub Actions macOS runner compiles the app and packages an **unsigned** `.ipa`;
2. you download that `.ipa`;
3. you **sign it on the iPhone** with your own certificate and install it.

Signing never happens in CI — no Apple private key or provisioning profile is stored in the repository or in Actions secrets.

## Pipeline overview

```text
push tag v*  ─┐
              ├─► macOS runner (macos-15)          ─► artifact "ios-ipa-unsigned" (7 days)
Run workflow ─┘     checkout
                    subosito/flutter-action@v2 (Flutter 3.47.7 stable, cached)
                    flutter pub get
                    flutter build ios --release --no-codesign
                    check build/ios/iphoneos/Runner.app exists, print metadata
                    Payload/Runner.app -> zip -> DSH-Remote-unsigned.ipa
                    print size + SHA-256
                                                                │
                            download (browser or `gh run download`)
                                                                ▼
                                   sign on iPhone with BuildBox 2.0 (or ESign/SideStore)
                                                                │
                                                                ▼
                                                       install and run
```

Workflow file: `.github/workflows/ios-ipa.yml`. A macOS build usually takes 6–15 minutes (the first run is slower because the Flutter SDK cache is cold).

## What the artifact contains

| Item | Value |
| --- | --- |
| Artifact name | `ios-ipa-unsigned` |
| Retention | 7 days |
| Files | `DSH-Remote-unsigned.ipa`, `DSH-Remote-unsigned.ipa.sha256` |
| Bundle id | `com.dsh.remote` (see `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`) |
| Version | from `version:` in `pubspec.yaml` (`3.2.0+23` → short version `3.2.0`, build `23`) |
| Signing state | unsigned: no `_CodeSignature`, no `embedded.mobileprovision` |

An unsigned IPA **cannot be installed by iOS**. It must be signed first — that is the whole point of the second half of this document.

## Prerequisites

- Access to the GitHub repository (the workflows run on the repository's Actions).
- An iPhone with iOS 17.0 or later for BuildBox 2.0.
- Signing assets for the device: a **certificate** (`.p12` + its password) and a **provisioning profile** (`.mobileprovision`), both bound to the Apple ID that will install the app.
  - A **free Apple ID** is enough to sideload. Free provisioning expires after 7 days and is limited in the number of apps and App IDs (see [Free Apple ID limits](#free-apple-id-limits)).
  - A **paid Apple Developer Program** account removes the 7-day expiry and the app-count limits.
- Optional but recommended: a working way to move a file from the computer to the iPhone — AirDrop (Mac), iCloud Drive, the Files app on iOS 13+, or a cloud drive.

No Mac is required at any step. If you do have one, `tools/build_ios.sh` reproduces the CI build locally.

## Build it in CI

### Triggers

| Trigger | How to start a build |
| --- | --- |
| `workflow_dispatch` | GitHub → **Actions** → **iOS IPA (unsigned)** → **Run workflow**, or `gh workflow run ios-ipa.yml` |
| Tag push matching `v*` | `git tag v3.2.0 && git push origin v3.2.0` |

Tag pushes are the release path: the tag should match the version in `pubspec.yaml` (see [CI.md](CI.md#bumping-the-version)).

### What the job does

The steps are named in the Actions UI, so a failure points directly at the stage:

1. **Checkout** – `actions/checkout@v7`.
2. **Select Xcode** – uses the runner default unless the repository variable `XCODE_APP` is set (escape hatch for Xcode drift, see [troubleshooting](#troubleshooting)).
3. **Set up Flutter** – `subosito/flutter-action@v2`, `flutter-version: 3.47.7`, `channel: stable`, `cache: true`.
4. **Resolve dependencies** – `flutter pub get`.
5. **Build iOS (release, no codesign)** – `flutter build ios --release --no-codesign`.
6. **Verify Runner.app and read app metadata** – fails loudly if `build/ios/iphoneos/Runner.app` is missing, prints bundle id/version, warns if the "unsigned" build unexpectedly carries signing files.
7. **Package Payload/Runner.app into an unsigned .ipa** – copies the app to `Payload/Runner.app`, `zip -r -y` (symlinks preserved), prints the IPA listing, size and SHA-256.
8. **Write job summary** – version, bundle id, size, SHA-256 in the run summary.
9. **Upload unsigned IPA** – artifact `ios-ipa-unsigned`, `if-no-files-found: error`, retention 7 days.

## Build locally on a Mac (optional)

If you happen to have a Mac, `tools/build_ios.sh` reproduces the CI build and writes the same artifact locally:

```bash
chmod +x tools/build_ios.sh   # once, if the executable bit was lost (e.g. a Windows checkout)
tools/build_ios.sh            # or: bash tools/build_ios.sh
```

It runs `flutter pub get`, `flutter build ios --release --no-codesign`, packages `Payload/Runner.app` into `dist/DSH-Remote-unsigned.ipa`, and prints the size plus SHA-256 (also written to `dist/DSH-Remote-unsigned.ipa.sha256`). It requires macOS, Xcode with the command line tools (`xcode-select -s /Applications/Xcode.app`), and Flutter 3.47.7 stable; it warns when the local Flutter version differs from the CI pin.

The script is written for the bash 3.2 that ships with macOS — no Homebrew bash needed.

## Download the artifact

### From the browser

1. Open the repository on GitHub → **Actions** → **iOS IPA (unsigned)**.
2. Click the run you want (a tag build is named after the tag).
3. In the run summary scroll to **Artifacts** and download `ios-ipa-unsigned` (a `.zip`).
4. Unzip it: you get `DSH-Remote-unsigned.ipa` and `DSH-Remote-unsigned.ipa.sha256`.

### With the GitHub CLI

```bash
# List recent runs of the iOS workflow
gh run list --workflow=ios-ipa.yml --limit 5

# Wait for the latest run to finish (optional)
gh run watch

# Download the artifact of a specific run into ./dist
gh run download <run-id> -n ios-ipa-unsigned -D dist
```

On a tag build you can list only tag-triggered runs:

```bash
gh run list --workflow=ios-ipa.yml --event=push --limit 5
```

### Verify the download

```bash
cd dist
shasum -a 256 -c DSH-Remote-unsigned.ipa.sha256
```

On Windows PowerShell:

```powershell
Get-FileHash .\DSH-Remote-unsigned.ipa -Algorithm SHA256
# compare with the value printed in the workflow log / job summary
```

Private repositories: artifacts are only downloadable by accounts with repository access, and only while the artifact has not expired (7 days).

## Sign and install on-device with BuildBox 2.0

[BuildBox](https://github.com/mikevillarroel/buildbox-ios) is an iPhone app that compiles and **signs and installs any IPA on-device** with your own certificate (zsign, no Mac, no PC, no upload to a signing service). The release IPA of BuildBox itself is unsigned, so the first install of BuildBox needs an existing signer (AltStore, SideStore, ESign, Sideloadly, …).

### Step 1 — install BuildBox on the iPhone

1. Download `BuildBox-<version>.ipa` from the [latest BuildBox release](https://github.com/mikevillarroel/buildbox-ios/releases/latest).
2. Sideload it with the signer you already have (AltStore/SideStore/ESign/Sideloadly) using your certificate. This is a one-time step: after BuildBox is installed you can sign DSH Remote with it.
3. If iOS shows "Untrusted Developer" on first launch, trust the certificate: **Settings → General → VPN & Device Management → \<your developer certificate\> → Trust**.

### Step 2 — import the signing certificate

In BuildBox open the **Sign** tab and import:

- the certificate `.p12` file and its password;
- the provisioning profile `.mobileprovision` file.

Both files must belong to the same Apple team and must include the device UDID (development or ad-hoc profile; App Store profiles do not work for sideloading).

Where the files come from:

- **Paid Apple Developer Program**: Certificates, Identifiers & Profiles → create an iOS Development certificate and a development/ad-hoc provisioning profile for App ID `com.dsh.remote` (or a wildcard `com.dsh.*`). Export the certificate with its private key as `.p12` from Keychain Access (macOS) or from the tool you used to generate the key pair.
- **Free Apple ID**: free accounts cannot download a `.p12` from the developer portal; signers that log in with the Apple ID (AltStore, SideStore, ESign) generate the certificate and profile themselves. Export/reuse that certificate if your tool allows it, otherwise sign the IPA directly with that tool instead of BuildBox.

Never commit a `.p12`, its password, or a `.mobileprovision` file to the repository.

### Step 3 — sign the app

1. In the **Sign** tab, import `DSH-Remote-unsigned.ipa` (from the Files app, or share it to BuildBox).
2. If the provisioning profile is bound to a different App ID than `com.dsh.remote`, edit **Bundle ID** in BuildBox so it matches the profile (a wildcard profile such as `com.dsh.*` accepts any bundle id under that prefix).
3. Optionally edit the display name and version; the version already comes from `pubspec.yaml`.
4. Tap **Sign** and wait for the log to report success.

### Step 4 — install

1. Open the BuildBox **Library** tab, find the signed app.
2. Swipe left → **Install** (BuildBox serves the signed IPA over local HTTPS; confirm the iOS installation prompts).
3. Launch DSH Remote. If iOS asks to enable **Developer Mode** (Settings → Privacy & Security → Developer Mode), enable it and reboot.
4. If the app is still refused, trust the certificate again under **Settings → General → VPN & Device Management**.

## Alternative signers

Any tool that signs an IPA with your certificate and installs it works; BuildBox just removes the computer from the loop.

| Tool | Runs on | Needs a computer? | Notes |
| --- | --- | --- | --- |
| [BuildBox 2.0](https://github.com/mikevillarroel/buildbox-ios) | iPhone | No (after BuildBox itself is sideloaded) | Imports `.p12` + `.mobileprovision`; edits bundle id/name/version; installs over local HTTPS |
| ESign | iPhone | No | Imports certificate + IPA, signs and installs on-device; can also install BuildBox |
| SideStore | iPhone | One-time pairing with a computer for the first install | Free Apple ID flow; re-signs before the 7-day expiry |
| AltStore | iPhone + AltServer on macOS/Windows | Yes (AltServer) | Free Apple ID flow; re-signs weekly |
| Sideloadly | Windows/macOS | Yes | Signs and installs over USB/Wi-Fi |
| Feather | iPhone | No | On-device signing/installing, certificate import |

Third-party signers are not Apple software. Use the official project releases, prefer open source, and only ever sign an IPA you built yourself.

## Free Apple ID limits

Sideloading with a free Apple ID works, but Apple imposes limits:

- **7-day expiry** — the app stops launching after 7 days. Re-sign it with the same certificate (BuildBox/AltStore/SideStore); a new CI build is only needed if you also changed the app.
- **3 apps** signed with a free certificate can be installed on the device at the same time.
- **10 new App IDs per 7 days** — repeated bundle-id edits consume this quota.
- **2-factor authentication** is required on the Apple ID.
- No entitlements (push, iCloud, App Groups, …) and no TestFlight/App Store distribution.

A paid Apple Developer Program membership removes the 7-day expiry and the app-count limits, and lets you use a 1-year development or ad-hoc profile.

## Runtime notes for this app

- **Local network permission.** iOS 14+ asks "…would like to find and connect to devices on your local network" the first time the app talks to the PC. The app cannot reach the DSH host on your LAN if you decline. The prompt is controlled by `NSLocalNetworkUsageDescription` in `ios/Runner/Info.plist` (required — without it the connection fails without a usable prompt). Re-enable it under **Settings → Privacy & Security → Local Network → DSH Remote** (toggle off/on) and relaunch the app.
- **Cleartext HTTP / App Transport Security.** DSH Remote talks plain HTTP to the PC's LAN IP (or Tailscale IP), so `ios/Runner/Info.plist` must allow it via `NSAppTransportSecurity → NSAllowsArbitraryLoads = true`. Without it, requests fail with an ATS error ("cleartext HTTP … is not permitted"). If you later move to HTTPS with a trusted certificate, remove that exception.
- **Camera and photo library.** Scanning the pairing QR code uses the camera; sending images uses the photo library. Both prompts come from `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` in `Info.plist`.
- **Files app access.** `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` expose the app's Documents directory in the Files app (downloaded/shared files land there).
- **PC-side reachability.** The phone and the PC must be on the same LAN (or reachable over Tailscale/VPN), the `dsh-mobile-remote` plugin must be listening, and the PC firewall must allow the port. Use the QR code from the DSH settings page to fill in address + token.

## Troubleshooting

### "Expected build output missing: build/ios/iphoneos/Runner.app" (CI)

The packaging step runs after a successful build, so this error normally means the build step just above already failed, or `flutter build ios` wrote its output elsewhere. Look at the **Build iOS (release, no codesign)** step log; the usual causes are listed in the next two sections. Locally the same check lives in `tools/build_ios.sh`, which prints `build/ios` when the directory is missing.

If Flutter genuinely produced the app under a different path (for example after switching build subcommands), adjust `APP_PATH` in `.github/workflows/ios-ipa.yml` and `tools/build_ios.sh` together.

### SPM vs CocoaPods plugin failures

This project builds with **Swift Package Manager** enabled: `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/` exists and there is no committed `ios/Podfile`. Flutter builds a Swift package for the plugins; that is why iOS needs no `pod install` here.

Symptoms and fixes:

- A plugin that does not ship SPM support makes Flutter fall back to CocoaPods. It then expects an `ios/Podfile`; if the file is missing you may see errors about a missing Podfile, a missing `Pods.xcodeproj`, or "Unable to find a specification for …". Generate and commit the Podfile once by running `flutter build ios --release --no-codesign` locally, or check whether a newer plugin version supports SPM.
- `pod install` sandbox/`Pods are out of sync` errors: `cd ios && pod install --repo-update` (the macOS runner has CocoaPods 1.17 preinstalled).
- To force the CocoaPods path: `flutter config --no-enable-swift-package-manager`, then `rm -rf ios/Flutter/ephemeral ios/Pods ios/Podfile.lock` and rebuild. Re-enable with `flutter config --enable-swift-package-manager`. Keep the local decision consistent with what is committed — mixing both paths is the most common source of "works locally, fails in CI".
- Plugin compilation errors ("module not found", generated registrant mismatches) after changing dependencies: `flutter clean && flutter pub get`, then rebuild.

### Xcode / Flutter version drift

The workflow pins Flutter (`3.47.7`) but the macOS runner image keeps its own Xcode set (in the 2026 `macos-15` images the default is Xcode 16.4, with newer Xcode versions also installed). A Flutter upgrade can require a newer Xcode than the image default, and a runner image update can move the default.

- If the build fails with an Xcode/SDK mismatch, pin an Xcode that is installed on the runner: create a repository variable `XCODE_APP` (Settings → Secrets and variables → Actions → **Variables**) with an absolute path such as `/Applications/Xcode_26.3.app`. The **Select Xcode** step runs `sudo xcode-select -s` for you.
- See what an image provides in the [runner images repository](https://github.com/actions/runner-images/tree/main/images/macos) (`macos-15` readme lists the installed Xcode versions).
- Locally, `tools/build_ios.sh` prints the Xcode version and warns when the Flutter version differs from the CI pin.
- Flutter's minimum Xcode requirement is part of each release's upgrade notes; when bumping Flutter, bump the Xcode selection in the same change.

### Bundle id / provisioning profile mismatch (signing fails or install is rejected)

Typical messages: "Provisioning profile doesn't include signing certificate", "The App ID … does not match the profile", "Unable to install".

- The signed bundle id must equal the profile's App ID, or fall under a wildcard profile (`com.dsh.*`). The app is built with `com.dsh.remote`; either create the profile for exactly `com.dsh.remote`, or edit the bundle id in BuildBox to match the profile you have.
- Certificate and profile must come from the same team; a revoked or expired certificate is rejected — generate a new one.
- Development/ad-hoc profiles must contain the device UDID. App Store profiles cannot side-load.
- After changing the bundle id in `ios/Runner.xcodeproj`, rebuild in CI so the IPA matches what you are signing.

### "Untrusted Developer" / app does not launch

Trust the signing certificate: **Settings → General → VPN & Device Management → \<certificate\> → Trust**. On iOS 16+, apps built with development signing may additionally need **Developer Mode** (Settings → Privacy & Security → Developer Mode → on, then reboot).

### "Unable to install … integrity could not be verified"

The IPA was truncated or not signed correctly. Re-download the artifact, verify the SHA-256, and re-sign. Check that the signer reported success in its log.

### The artifact is gone

Artifacts expire after 7 days. Re-run the workflow (Actions → the workflow → **Run workflow**, or `gh workflow run ios-ipa.yml`) to produce a fresh artifact.

### The app stopped working after a week

The free Apple ID certificate expired. Re-sign the IPA on the device (BuildBox/AltStore/SideStore). Re-downloading is only needed if you also want a new build.

### CI minutes / cost

GitHub Actions is free for public repositories. Private repositories consume the monthly included minutes, and macOS runners are billed at **10×** the Linux rate — an 8-minute iOS build counts as ~80 minutes, so keep `workflow_dispatch` for release builds rather than building on every push.

## Related documents

- [CI.md](CI.md) — workflows, re-running builds, artifacts, version bumping, Android signing.
- `README.md` — feature overview and Android build/signing notes.
