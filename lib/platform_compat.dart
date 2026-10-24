// iOS 移植：平台判定的单一来源，避免各处各写一套 Platform / defaultTargetPlatform。
//
// 两个判定刻意不同源：
// - [DshPlatform.isAndroid] 用 dart:io `Platform`：面向**原生通道**（如 `dsh/floating`、
//   `dsh/files`）。测试宿主是 Windows，恒为 false，保证 widget/单元测试绝不会打到未注册的
//   Android-only 通道（否则 `MissingPluginException` 会随机冒出来）。
// - [DshPlatform.isIOS] 用 `defaultTargetPlatform`：面向**UI 分支**（隐藏 Android-only 选项、
//   iOS 状态栏等）。widget 测试可用 `debugDefaultTargetPlatformOverride` 模拟 iOS 断言。
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class DshPlatform {
  DshPlatform._();

  /// 真实宿主是否为 Android（原生通道的开关依据）。
  static bool get isAndroid => Platform.isAndroid;

  /// 目标平台是否为 iOS（UI 分支依据；测试可覆盖）。
  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
}
