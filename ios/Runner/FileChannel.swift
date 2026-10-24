import Flutter
import UIKit
import UniformTypeIdentifiers

/// Registers the app-level MethodChannels that the Android host implements in
/// `MainActivity.kt`.
///
/// The Dart side (`lib/screens/chat_screen.dart`, `lib/floating.dart`) owns the
/// contract; this file mirrors it on iOS:
/// - `dsh/files`
///     - `pickFile` -> `{name: String, bytes: FlutterStandardTypedData}` or `nil`
///       when the user cancels. Presented with `UIDocumentPickerViewController`.
///     - `saveToDownloads {name: String, bytes: FlutterStandardTypedData}` ->
///       absolute path `String` of the written file under
///       `Documents/Downloads/<name>`.
///     - unknown methods -> `FlutterMethodNotImplemented`.
/// - `dsh/floating` is a no-op because the floating bubble is an Android-only
///   system capability. It is still registered so a Dart call can never raise
///   `MissingPluginException`; boolean probes answer `false` and everything
///   else answers `nil`.
enum DshChannels {
  private static var fileChannel: FileChannel?
  private static var floatingChannel: FlutterMethodChannel?

  /// Registers all app-level channels on [messenger].
  ///
  /// Call once, after the implicit Flutter engine is initialized (see
  /// `AppDelegate.didInitializeImplicitFlutterEngine`). Keeps strong
  /// references so channel handlers and the document picker delegate stay
  /// alive for the lifetime of the engine.
  static func register(with messenger: FlutterBinaryMessenger) {
    fileChannel = FileChannel(messenger: messenger)

    let floating = FlutterMethodChannel(name: "dsh/floating", binaryMessenger: messenger)
    floating.setMethodCallHandler { call, result in
      switch call.method {
      case "isRunning", "canDrawOverlay":
        result(false)
      default:
        // start/stop/openOverlaySettings/notifyBalance/setBalanceAlert are
        // void on the Dart side; consumeOpenPanel expects a nullable String.
        result(nil)
      }
    }
    floatingChannel = floating
  }
}

/// iOS implementation of the `dsh/files` MethodChannel.
final class FileChannel: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel

  /// Result of the in-flight `pickFile` call. Non-nil while the document
  /// picker is on screen; guards against overlapping pick requests.
  private var pendingPick: FlutterResult?

  private static let downloadsFolderName = "Downloads"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dsh/files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "FileChannel is no longer available",
            details: nil
          )
        )
        return
      }
      self.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickFile":
      pickFile(result: result)
    case "saveToDownloads":
      saveToDownloads(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickFile

  private func pickFile(result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      result(FlutterError(code: "busy", message: "already picking", details: nil))
      return
    }
    pendingPick = result
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard let presenter = FileChannel.topViewController() else {
        self.finishPick(
          FlutterError(
            code: "no-presenter",
            message: "Unable to find a view controller to present the document picker",
            details: nil
          )
        )
        return
      }
      // `.item` (public.item) matches Android's `*/*` document intent: any file.
      // `asCopy: true` hands the app a local copy, so no security scoped access
      // is required to read it.
      let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.item],
        asCopy: true
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      presenter.present(picker, animated: true)
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let url = urls.first else {
      finishPick(nil)
      return
    }
    // Read off the main thread: uploaded files can be large.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let isScoped = url.startAccessingSecurityScopedResource()
      defer {
        if isScoped { url.stopAccessingSecurityScopedResource() }
      }
      do {
        let data = try Data(contentsOf: url)
        DispatchQueue.main.async {
          self?.finishPick([
            "name": url.lastPathComponent,
            "bytes": FlutterStandardTypedData(bytes: data),
          ])
        }
      } catch {
        DispatchQueue.main.async {
          self?.finishPick(
            FlutterError(
              code: "read-failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // The Dart caller treats `null` as "user cancelled" (`if (picked == null)
    // return;`); answer with null instead of an error so cancelling does not
    // surface as an upload failure toast.
    finishPick(nil)
  }

  private func finishPick(_ value: Any?) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    result(value)
  }

  // MARK: - saveToDownloads

  private func saveToDownloads(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad-args", message: "missing arguments", details: nil))
      return
    }
    guard let typedBytes = arguments["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(code: "bad-args", message: "missing bytes", details: nil))
      return
    }
    let name = FileChannel.sanitizedFileName(arguments["name"] as? String)
    let data = typedBytes.data

    // Write off the main thread: downloads from the PC can be large.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let destination = try FileChannel.write(data: data, named: name)
        DispatchQueue.main.async {
          result(destination.path)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "save-failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  /// Writes [data] to `Documents/Downloads/[name]` and returns the file URL.
  ///
  /// `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` (both set
  /// in Info.plist) make this directory visible in the Files app.
  private static func write(data: Data, named name: String) throws -> URL {
    let documents = try FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = documents.appendingPathComponent(downloadsFolderName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let destination = uniqueDestination(in: directory, fileName: name)
    try data.write(to: destination, options: .atomic)
    return destination
  }

  /// Never overwrites an existing download; appends " (1)", " (2)", ...
  private static func uniqueDestination(in directory: URL, fileName: String) -> URL {
    let candidate = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: candidate.path) else {
      return candidate
    }
    let fileExtension = candidate.pathExtension
    let stem = candidate.deletingPathExtension().lastPathComponent
    var index = 1
    while true {
      let suffix = " (\(index))"
      let nextName = fileExtension.isEmpty
        ? "\(stem)\(suffix)"
        : "\(stem)\(suffix).\(fileExtension)"
      let next = directory.appendingPathComponent(nextName)
      if !FileManager.default.fileExists(atPath: next.path) {
        return next
      }
      index += 1
    }
  }

  /// Keeps the last path component only, so a name from the PC (which may
  /// contain `/` or `\`) cannot escape `Documents/Downloads`.
  private static func sanitizedFileName(_ raw: String?) -> String {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else {
      return "file"
    }
    let lastComponent = (raw as NSString).lastPathComponent
    let cleaned = lastComponent
      .replacingOccurrences(of: "\\", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
      return "file"
    }
    return cleaned
  }

  // MARK: - UIKit helpers

  /// Topmost view controller of the key window of the connected UIWindowScene.
  /// This app uses the UIScene lifecycle (see `SceneDelegate.swift`), so
  /// `UIApplication.shared.keyWindow` is not used.
  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    var controller = keyWindow?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
