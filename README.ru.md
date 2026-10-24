# DSH Remote — управление DeepSeek Harness с телефона

Нативное мобильное приложение (Flutter) для **DeepSeek Harness**: отправляйте задачи
агенту, который работает на компьютере, смотрите потоковые ответы, подтверждайте вызовы
инструментов, отвечайте на вопросы, просматривайте сессии, файлы и уведомления — по
локальной сети, без облака.

Этот репозиторий — форк [`201222-L/dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote)
(MIT). В апстриме есть плагин для DSH и Android-приложение; **здесь добавлена полноценная
поддержка iOS** и сборка `.ipa` без Mac (через GitHub Actions).

| Платформа | Статус | Артефакт |
| --- | --- | --- |
| Android 7.0+ | ✅ собран, 379 тестов проходят | `app-release.apk` |
| iOS 15.0+ | ✅ портирован, IPA собирается на macOS-раннере GitHub | `DSH-Remote-unsigned.ipa` (подписать на iPhone) |

## Как это работает

```
Телефон (приложение) ──HTTP/SSE──►  плагин dsh-mobile-remote  ──►  DSH на компьютере
                                    (тот же протокол, что у десктопного GUI)
```

Компьютер остаётся единственным источником истины: сессии, история, права и настройки
моделей живут в DSH. Приложение — тонкий real-time клиент, состояние не дублируется.

## Что нужно

- Компьютер с **DeepSeek Harness** и включённым плагином
  [`dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote)
  (плагин `v3.x`, ядро DSH `0.1.2-rc.1` / DSH Desktop `v2.0.5` или новее).
- Телефон и компьютер в одной сети (или в приватной сети вроде Tailscale).
- На компьютере: **Настройки → «Подключить мобильное устройство»** — там QR-код.

> ⚠️ Безопасность: токен из QR-кода — единственный ключ доступа. Для каждого компьютера
> свой токен, порт плагина нельзя выставлять в интернет, QR-код считайте паролем.

## Быстрый старт

1. На компьютере: установить и включить `dsh-mobile-remote`, открыть «Настройки →
   Подключить мобильное устройство».
2. На телефоне: установить приложение (APK или подписанный IPA — см. ниже).
3. В приложении нажать **«Сканировать»** и отсканировать QR-код — либо ввести адрес
   (`http://192.168.x.x:3080`) и токен вручную.
4. Отправить сообщение с главного экрана и смотреть, как работает агент.

Язык интерфейса переключается между китайским и английским в *Настройках → Язык*
(русской локализации пока нет).

## Сборка из исходников

Зафиксированный тулчейн: Flutter **3.47.7** (Dart 3.13.5).

```bash
flutter pub get
flutter analyze          # No issues found!
flutter test             # 379 тестов
```

### Android

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Для релизной подписи положите `android/key.properties` и keystore (файлы `*.jks` в
.gitignore); без них сборка подписывается debug-ключом.

### iOS

Для сборки нужен Xcode/macOS. Два варианта:

1. **GitHub Actions (Mac не нужен)** — запустить workflow **iOS IPA (unsigned)**, он
   выдаст неподписанный `.ipa`. Затем подписать его на iPhone через BuildBox 2.0 или
   AltStore/SideStore. Подробно: [`docs/IOS-BUILD.md`](docs/IOS-BUILD.md) и пошаговая
   инструкция [`docs/INSTALL-iOS.ru.md`](docs/INSTALL-iOS.ru.md).
2. **Локально на macOS** — `tools/build_ios.sh` → `dist/DSH-Remote-unsigned.ipa`.

iOS-таргет использует Swift Package Manager (Podfile не нужен), минимальная версия
iOS 15.0, bundle id `com.dsh.remote`.

## Что изменено при портировании на iOS

- `ios/Runner/Info.plist` — разрешения камеры и фото, **локальная сеть** (обязательно на
  iOS 14+ для HTTP в LAN), исключение ATS для открытого HTTP к локальным адресам,
  доступ к файлам через приложение «Файлы».
- `ios/Runner/FileChannel.swift` — нативная реализация method channel `dsh/files`:
  выбор документа для загрузки, сохранение вложений в `Documents/Downloads/`.
- `lib/platform_compat.dart`, `lib/files_channel.dart` — слой платформенных решений.
  Плавающий шарик (системный оверлей Android) на iOS неактивен, его настройки скрыты;
  на iOS работают нативный свайп-назад, Cupertino-переходы и корректный статус-бар.
- `.github/workflows/ios-ipa.yml` — сборка неподписанного IPA на `macos-15`.

Не портировано: плавающий шарик, foreground service Android. iOS-push не реализован —
пуш-мост плагина (Server酱/ntfy/Bark) работает независимо от приложения.

## Структура репозитория

```
lib/            Flutter UI + API/SSE клиент (код апстрима, адаптирован под iOS)
ios/            iOS Runner, Info.plist, иконки, Swift-каналы
android/        Android Runner (без изменений)
test/           379 unit/widget тестов
.github/        CI: неподписанный IPA + release APK
docs/           гайды по сборке/подписи iOS (EN + RU), заметки по CI
tools/          build_ios.sh, генератор иконок
```

## Лицензия и авторство

MIT — см. [LICENSE](LICENSE) и [NOTICE.md](NOTICE.md). Оригинальный проект:
[`201222-L/dsh-mobile-remote`](https://github.com/201222-L/dsh-mobile-remote) © его авторы;
этот форк добавляет поддержку iOS и CI.
