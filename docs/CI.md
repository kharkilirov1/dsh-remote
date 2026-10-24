# Continuous integration

Two GitHub Actions workflows build installable artifacts of the Flutter app. Both are manual-first and also run on release tags; nothing is built on ordinary branch pushes.

| Workflow | File | Runner | Triggers | Artifact | Contents | Retention |
| --- | --- | --- | --- | --- | --- | --- |
| **iOS IPA (unsigned)** | `.github/workflows/ios-ipa.yml` | `macos-15` | `workflow_dispatch`, push tag `v*` | `ios-ipa-unsigned` | `DSH-Remote-unsigned.ipa`, `DSH-Remote-unsigned.ipa.sha256` | 7 days |
| **Android APK** | `.github/workflows/android-apk.yml` | `ubuntu-latest` | `workflow_dispatch`, push tag `v*` | `android-apk` | `app-release.apk`, `app-release.apk.sha256` | 7 days |

Both jobs use `permissions: contents: read`, a `concurrency` group per ref (a re-run of the same tag cancels the previous run), and fail loudly when the expected build output is missing. Mobile signing details are in [IOS-BUILD.md](IOS-BUILD.md).

## Repository layout assumption

These workflows assume the **Flutter project is the repository root** (`pubspec.yaml`, `ios/`, `android/` at the top level).

If the app instead lives in a subdirectory (for example `app/`), move these two files to the repository's top-level `.github/workflows/`, add `defaults: { run: { working-directory: app } }` to each job, and prefix the artifact paths with `app/`.

## Running and re-running builds

Start a build:

```bash
# iOS unsigned IPA
gh workflow run ios-ipa.yml

# Android APK
gh workflow run android-apk.yml

# Watch the most recent run
gh run list --limit 5
gh run watch
```

Or use the GitHub UI: **Actions** → select the workflow → **Run workflow** (choose the branch).

Re-run an existing run:

```bash
# Re-run everything for a specific run
gh run rerun <run-id>

# Re-run only the failed jobs
gh run rerun <run-id> --failed
```

The UI equivalent is **Re-run all jobs** / **Re-run failed jobs** on the run page.

Release tags: pushing a tag matching `v*` builds both artifacts for that commit. Prefer re-running the workflow over deleting and re-pushing a tag — a moved tag produces two runs pointing at different commits and confuses artifact provenance.

## Downloading artifacts

- **UI**: open the run page → **Artifacts** → click the artifact to download a zip.
- **CLI**:

```bash
gh run list --workflow=android-apk.yml --limit 5
gh run download <run-id> -n android-apk -D dist
gh run download <run-id> -n ios-ipa-unsigned -D dist
```

Each artifact is a zip containing the build and its `.sha256` file. Verify after downloading:

```bash
cd dist && sha256sum -c app-release.apk.sha256       # Android artifact
cd dist && shasum -a 256 -c DSH-Remote-unsigned.ipa.sha256   # iOS artifact (macOS/Linux)
```

On Windows PowerShell use `Get-FileHash -Algorithm SHA256` and compare with the value printed in the workflow log or the run summary.

Artifacts expire after 7 days and private-repository artifacts require repository access.

## Bumping the version

The single source of truth is `version:` in `pubspec.yaml`:

```yaml
version: 3.2.0+23
#        ^^^^^  ^^
#        name   build number
```

What it controls:

- **Android** – `versionName = 3.2.0`, `versionCode = 23` (`android/app/build.gradle.kts` reads `flutter.versionName` / `flutter.versionCode`).
- **iOS** – `CFBundleShortVersionString = 3.2.0`, `CFBundleVersion = 23` (Flutter writes `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` into `ios/Flutter/Generated.xcconfig`).
- **In the app** – Settings → **Version** shows `App v3.2.0+23` (read at runtime via `package_info_plus`, so a rebuild is required for it to change).

Bump procedure:

1. Edit `pubspec.yaml` → `version: <new-name>+<new-build>`. Bump the build number for every build you distribute, even when the name stays the same.
2. Commit the change.
3. Tag the commit with the same name: `git tag v3.2.0 && git push origin v3.2.0`. Both workflows build the tag and produce the artifacts with the new version baked in.
4. Optionally create a GitHub Release from the tag; the artifacts stay on the workflow run (link them from the release notes).
5. Keep the plugin version in sync when the protocol changes: `dsh-mobile-remote`'s `package.json` version and this app's `pubspec.yaml` version are released together (see the repository README).

Do not edit `pubspec.lock`, `ios/Flutter/Generated.xcconfig` or the Gradle version fields directly; they are generated from `pubspec.yaml`.

## Android release signing

`android/app/build.gradle.kts` signs release builds with `android/key.properties` when that file exists, and otherwise falls back to the **debug** key so that a clean clone (and CI) can build. The CI artifact is therefore debug-signed: installable, but not suitable for Play Store upload.

To ship a properly signed APK:

1. Create a keystore outside the repository, e.g. `keytool -genkeypair -v -keystore dsh-release.jks -keyalg RSA -keysize 2048 -validity 10950 -alias dsh`.
2. Add the keystore and the `key.properties` contents as repository secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`) and decode them in a workflow step before `flutter build apk --release`.
3. Never commit `android/key.properties` or the `.jks` file. Note that the current root `.gitignore` does **not** list them yet — add both patterns before creating any keystore, otherwise `git add -A` will pick them up.

## Cost

GitHub Actions is free for public repositories. Private repositories spend the monthly included minutes, and macOS runners are billed at **10×** the Linux rate — the iOS job (typically 6–15 minutes, longer on a cold cache) consumes roughly 60–150 billed minutes per build. That is why both workflows are manual/tag-driven instead of building on every push.

## Workflow maintenance

Action versions are pinned to the current Node 24 majors, because GitHub removed the Node 20 runtime from its runners on 23 September 2026 ([changelog](https://github.blog/changelog/2025-09-19-deprecation-of-node-20-on-github-actions-runners/)): `actions/checkout@v7`, `actions/upload-artifact@v7`, `actions/setup-java@v6`. `subosito/flutter-action@v2` is a composite action and internally uses `actions/cache@v5`.

When updating an action, check that its `runs.using` is `node24` (or `composite`) and read the release notes for breaking input changes:

```bash
# What runtime does an action declare at a given tag?
curl -fsSL https://raw.githubusercontent.com/actions/upload-artifact/v7/action.yml | grep 'using:'
```

Validate the workflow files locally before pushing:

```bash
# YAML syntax (js-yaml CLI; any YAML parser works)
npx --yes js-yaml .github/workflows/ios-ipa.yml > /dev/null && echo "ios-ipa.yml ok"
npx --yes js-yaml .github/workflows/android-apk.yml > /dev/null && echo "android-apk.yml ok"

# Real GitHub Actions linting (Go binary, no repository dependency)
#   https://github.com/rhysd/actionlint/releases
actionlint .github/workflows/ios-ipa.yml .github/workflows/android-apk.yml

# Shell: the CI scripts and tools/build_ios.sh must stay bash 3.2 compatible.
# macOS ships bash 3.2, so avoid associative arrays, ${var,,}, mapfile and
# other bash 4 features.
shellcheck -s bash tools/build_ios.sh
```

Keep the Flutter version pin (`3.47.7`) identical in `.github/workflows/ios-ipa.yml`, `.github/workflows/android-apk.yml`, `tools/build_ios.sh` and the docs.

## Troubleshooting

| Symptom | Where to look |
| --- | --- |
| iOS job fails at "Checkout"/"Set up Flutter" | Network or action-version issue; check the step log and `gh run view <run-id> --log-failed` |
| iOS build fails at compile/link | Xcode/Flutter drift, SPM vs CocoaPods plugin issues — see [IOS-BUILD.md](IOS-BUILD.md#xcode--flutter-version-drift) |
| "Expected build output missing" | The build step above failed; open that step's log |
| Android build fails in Gradle | JDK version (`java -version` step), Android SDK on the runner, or a dependency that needs a newer AGP |
| Artifact missing after a green run | upload step `if-no-files-found: error` would have failed the job; otherwise the artifact expired (7 days) |
