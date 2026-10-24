# NOTICE

This project is a derivative work of **DSH Remote** (`dsh-mobile-remote`):

- Upstream: https://github.com/201222-L/dsh-mobile-remote
- License: MIT (Copyright (c) the upstream authors)
- Upstream components reused here: the Flutter mobile app (`dsh-mobile-app/`) and its
  design/API client. The DSH plugin server that this app talks to is distributed by the
  upstream project and is not included in this repository.

Changes in this repository (2026):

- iOS platform port: `ios/` Runner project, `Info.plist` (camera, photo library, local
  network, ATS, file sharing), AppIcon/launch screen, `FileChannel.swift` native
  `dsh/files` implementation and a no-op `dsh/floating` channel.
- Dart platform-compatibility layer (`lib/platform_compat.dart`, `lib/files_channel.dart`)
  and iOS-specific UX adaptations; Android behavior unchanged.
- GitHub Actions workflows building an unsigned iOS IPA on macOS runners and a release
  Android APK.
- iOS build/signing documentation (English and Russian).

The MIT license text is in [LICENSE](LICENSE). Attribution to the upstream project is kept
in the README and in the app's source comments.
