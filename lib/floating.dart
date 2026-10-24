// 悬浮球（v2.7）：原生 overlay 服务桥接。
// 小球常驻系统上层（App 被杀仍工作），自己连 SSE 收事件；
// App 侧负责开关、权限引导、余额联动、面板页。
//
// iOS 移植：悬浮窗是 Android-only 系统能力，iOS 端没有（也不会有）原生实现。
// 所以所有方法在非 Android 平台直接返回默认值，**绝不调用 `dsh/floating` 通道**——
// 未注册的通道会抛 MissingPluginException，打断页面里的 async 链（启动恢复、设置页初始化）。
// 异步签名保持不变，调用点无需区分平台。
import 'package:flutter/services.dart';

import 'platform_compat.dart';

class Floating {
  static const _channel = MethodChannel('dsh/floating');

  /// 仅 Android 有原生实现；其它平台（iOS/测试宿主）一律空转。
  static bool get _available => DshPlatform.isAndroid;

  static Future<void> start() async {
    if (!_available) return;
    await _channel.invokeMethod('start');
  }

  static Future<void> stop() async {
    if (!_available) return;
    await _channel.invokeMethod('stop');
  }

  static Future<bool> isRunning() async {
    if (!_available) return false;
    return (await _channel.invokeMethod<bool>('isRunning')) ?? false;
  }

  /// 是否已授权悬浮窗权限（非 Android 平台恒为 false）。
  static Future<bool> canDrawOverlay() async {
    if (!_available) return false;
    return (await _channel.invokeMethod<bool>('canDrawOverlay')) ?? false;
  }

  /// 跳转系统悬浮窗权限设置页（非 Android 平台无操作）。
  static Future<void> openOverlaySettings() async {
    if (!_available) return;
    await _channel.invokeMethod('openOverlaySettings');
  }

  /// 余额刷新后同步给悬浮球（低余额时亮起 + 气泡）。value 为裸数字字符串（如 "10.50"），
  /// 币种固定 CNY（App 侧取值已 CNY 优先，原生 onBalance 也按此解析）。
  static Future<void> notifyBalance(double total) async {
    if (!_available) return;
    await _channel.invokeMethod('notifyBalance', {
      'value': total.toStringAsFixed(2),
    });
  }

  /// 余额预警配置同步给悬浮球（开关 + 阈值；悬浮球的报警判定完全以此为准，
  /// 开关关闭 → 悬浮球不因余额报警/亮起，仅常驻显示余额数值）。
  static Future<void> setBalanceAlert(bool enabled, double threshold) async {
    if (!_available) return;
    await _channel.invokeMethod('setBalanceAlert', {
      'enabled': enabled,
      'threshold': threshold.toStringAsFixed(2),
    });
  }

  /// 冷启动暂存的面板动作（一次性消费）：返回 `charge` | `notifs` | `session:<id>` | null。
  /// v2.7.2 review：原生侧投递后仍保留 pending 直到被消费，Dart 首帧后主动拉取，
  /// 解决"Dart handler 注册晚于投递"导致动作丢失。非 Android 平台恒为 null。
  static Future<String?> consumeOpenPanel() async {
    if (!_available) return null;
    return await _channel.invokeMethod<String>('consumeOpenPanel');
  }
}
