# DSH Remote

Native mobile client for **DeepSeek Harness (DSH)** — control the agent running on your
computer from your phone: send prompts, watch streaming replies, approve tool calls,
answer questions, browse sessions, files and notifications over your local network.

Built with Flutter. This repository is a fork of
[`201222-L/dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote) (MIT). The
upstream project ships the DSH plugin and an Android-only Flutter app; **this fork adds
full iOS support** and a Mac-free build path for an unsigned iPhone `.ipa`.

| Platform | Status | Artifact |
| --- | --- | --- |
| Android 7.0+ | ✅ built, tested (379 Flutter tests) | `app-release.apk` |
| iOS 15.0+ | ✅ ported, IPA built on GitHub macOS runners | `DSH-Remote-unsigned.ipa` (sign on device) |

## How it works

```
Phone (this app) ──HTTP/SSE──►  dsh-mobile-remote plugin  ──►  DeepSeek Harness on your PC
                                (same protocol as the desktop GUI)
```

The PC stays the single source of truth: sessions, history, permissions and model
settings live in DSH. The app is a thin, real-time client — nothing is stored twice.

## Requirements

- A computer running **DeepSeek Harness** with the
  [`dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote) plugin enabled
  (plugin `v3.x`, DSH core `0.1.2-rc.1` / DSH Desktop `v2.0.5` or newer).
- Phone and computer on the same network (or a private mesh such as Tailscale).
- The desktop plugin shows a **Connect mobile device** QR code under *Settings*.

> ⚠️ Security: the access token in the QR code is the only credential. Use a different
> token per computer, never expose the plugin port to the public internet, and treat the
> QR code as a password.

## Quick start

1. On the PC: install and enable `dsh-mobile-remote`, open **Settings → Connect mobile
   device**.
2. On the phone: install the app (APK / signed IPA — see below).
3. Open the app, tap **Scan to connect**, scan the QR code; or enter the address
   (`http://192.168.x.x:3080`) and token manually.
4. Send a message from the home screen and watch the agent work.

The UI language is switchable between Chinese and English in *Settings → Language*.

## Build from source

Flutter **3.47.7** (Dart 3.13.5) is the pinned toolchain.

```bash
flutter pub get
flutter analyze          # No issues found!
flutter test             # 379 tests
```

### Android

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Release signing: put `android/key.properties` + keystore (`*.jks` are git-ignored); without
them the build falls back to the debug key. See the upstream README for the `keytool`
recipe.

### iOS

iOS builds require Xcode/macOS. Two options:

1. **GitHub Actions (no Mac needed)** — run the **iOS IPA (unsigned)** workflow; it
   produces an unsigned `.ipa` artifact. Then sign it on the iPhone with BuildBox 2.0 or
   AltStore/SideStore. Full guide: [`docs/IOS-BUILD.md`](docs/IOS-BUILD.md) and the Russian
   step-by-step [`docs/INSTALL-iOS.ru.md`](docs/INSTALL-iOS.ru.md).
2. **Local macOS** — `tools/build_ios.sh` → `dist/DSH-Remote-unsigned.ipa`.

The iOS target uses Swift Package Manager (no Podfile); deployment target is iOS 15.0,
bundle id `com.dsh.remote`.

## iOS port notes

What changed relative to the upstream Android app:

- `ios/Runner/Info.plist` — camera/photo permissions, **local network** permission
  (required on iOS 14+ for LAN HTTP), ATS exception for plain HTTP to LAN hosts, file
  sharing so downloads appear in the Files app.
- `ios/Runner/FileChannel.swift` — native implementation of the `dsh/files` method
  channel: document picker for uploads, save to `Documents/Downloads/` for attachments.
- `lib/platform_compat.dart`, `lib/files_channel.dart` — platform decision layer. The
  floating bubble (an Android system overlay) is inert on iOS and its settings section is
  hidden; iOS gets native edge-swipe back, Cupertino page transitions and correct status
  bar contrast.
- `.github/workflows/ios-ipa.yml` — unsigned IPA build on `macos-15`.

Not ported (no iOS equivalent or out of scope): the floating bubble overlay, Android
foreground service. iOS push notifications are not implemented (the plugin's push bridge
works through Server酱/ntfy/Bark independently of this app).

## Repository layout

```
lib/            Flutter UI + API/SSE client (upstream code, iOS-adapted)
ios/            iOS Runner project, Info.plist, icons, Swift channels
android/        Android Runner (unchanged upstream)
test/           379 unit/widget tests
.github/        CI: unsigned IPA + release APK
docs/           iOS build/signing guides (EN + RU), CI notes
tools/          build_ios.sh, icon generator
```

## License and attribution

MIT — see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). Original project:
[`201222-L/dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote) © its authors;
this fork adds iOS support and CI.
