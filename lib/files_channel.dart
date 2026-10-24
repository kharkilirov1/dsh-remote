// `dsh/files` 原生通道的 Dart 侧封装。
//
// Android 由 MainActivity 的 MethodChannel 实现，iOS 由 Runner 的 Swift 实现同一组方法
// （pickFile / saveToDownloads）。通道缺失（iOS 原生未注册）或原生报错统一转成
// [FilesChannelError]，UI 只展示本地化文案，不再把 MissingPluginException /
// PlatformException 原样抛给用户。
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'platform_compat.dart';

/// `dsh/files` 通道失败；[message] 已是可直接展示给用户的本地化文案。
class FilesChannelError implements Exception {
  const FilesChannelError(this.message);

  final String message;

  @override
  String toString() => message;
}

class FilesChannel {
  FilesChannel._();

  static const MethodChannel _channel = MethodChannel('dsh/files');

  static String get unsupportedMessage => L10n.t(
    '当前平台暂不支持文件操作（原生组件未就绪）',
    'File operations are not available on this platform yet (native component missing)',
  );

  /// 打开系统文件选择器，返回所选文件名称与字节；用户取消返回 null。
  static Future<({String name, Uint8List bytes})?> pickFile() async {
    final Map<String, dynamic>? picked;
    try {
      picked = await _channel.invokeMapMethod<String, dynamic>('pickFile');
    } on MissingPluginException {
      throw FilesChannelError(unsupportedMessage);
    } on PlatformException catch (e) {
      if (_isCancellation(e)) return null;
      throw FilesChannelError(_messageFor(e));
    }
    if (picked == null) return null;
    final bytes = picked['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw FilesChannelError(L10n.t('读取文件失败', 'Failed to read the file'));
    }
    final name = picked['name'];
    return (
      name: (name is String && name.isNotEmpty) ? name : 'file',
      bytes: bytes,
    );
  }

  /// 保存字节到手机（Android：下载/外部目录；iOS：App 文档目录，经「文件」App 可见）。
  /// 返回原生侧给出的落盘路径（可能为 null）。
  static Future<String?> saveToDownloads({
    required String name,
    required Uint8List bytes,
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'name': name,
        'bytes': bytes,
      });
    } on MissingPluginException {
      throw FilesChannelError(unsupportedMessage);
    } on PlatformException catch (e) {
      throw FilesChannelError(_messageFor(e));
    }
  }

  /// 保存成功提示：Android 显示完整路径（文件管理器可定位）；iOS 沙盒路径对用户
  /// 无意义，只显示文件名。
  static String savedMessage(String? savedPath, String fallbackName) {
    final target = (savedPath == null || savedPath.isEmpty)
        ? fallbackName
        : savedPath;
    if (DshPlatform.isIOS) {
      final base =
          target.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ??
          target;
      return '${L10n.t('已保存到「文件」App：', 'Saved to Files: ')}$base';
    }
    return '${L10n.t('已保存到手机：', 'Saved on phone: ')}$target';
  }

  static bool _isCancellation(PlatformException e) {
    final code = e.code.toLowerCase();
    return code == 'cancelled' || code == 'canceled';
  }

  /// 原生错误 → 用户可读文案；权限类错误附带系统设置引导。
  ///
  /// 已知错误码来自 iOS Runner（ios/Runner/FileChannel.swift）：busy / no-presenter /
  /// read-failed / save-failed / unavailable / bad-args；Android 侧同类语义。未知码
  /// 回退到原生 message，仍保证是可展示的单行文案（不把异常对象抛给页面）。
  static String _messageFor(PlatformException e) {
    final code = e.code.toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        code.contains('unauthorized')) {
      return L10n.t(
        '没有文件访问权限，请在系统设置中允许本 App 访问文件',
        'No file access permission. Allow file access for this app in system settings',
      );
    }
    switch (code) {
      case 'busy':
        return L10n.t(
          '文件选择器已打开，请先完成当前选择',
          'A file picker is already open; finish it first',
        );
      case 'no-presenter':
        return L10n.t(
          '无法打开文件选择器，请稍后重试',
          'Unable to open the file picker, please try again',
        );
      case 'read-failed':
        return L10n.t('读取文件失败', 'Failed to read the file');
      case 'save-failed':
        return L10n.t('保存文件失败', 'Failed to save the file');
      case 'unavailable':
        return unsupportedMessage;
    }
    final detail = (e.message ?? '').trim();
    if (detail.isNotEmpty) {
      return '${L10n.t('文件操作失败：', 'File operation failed: ')}$detail';
    }
    return '${L10n.t('文件操作失败（', 'File operation failed (')}${e.code})';
  }
}
