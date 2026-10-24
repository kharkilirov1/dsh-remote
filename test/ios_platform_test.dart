// iOS 移植回归：Android-only 能力绝不触达平台通道；iOS 上隐藏对应 UI；
// 文件通道失败给本地化提示；iOS 使用原生 Cupertino 转场（边缘返回）与状态栏样式。
//
// 测试宿主是 Windows：`DshPlatform.isAndroid` 恒为 false，正好就是"非 Android"路径；
// UI 分支用 `debugDefaultTargetPlatformOverride` 模拟 iOS。
import 'package:dsh_mobile_app/files_channel.dart';
import 'package:dsh_mobile_app/floating.dart';
import 'package:dsh_mobile_app/l10n.dart';
import 'package:dsh_mobile_app/screens/settings_screen.dart';
import 'package:dsh_mobile_app/store.dart';
import 'package:dsh_mobile_app/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 注意：flutter_test 在测试体结束时（tearDown 之前）检查 foundation 调试变量，
  // 所以 override 必须在**测试体内**复位，不能用 addTearDown。
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.lang = 'zh';
  });

  group('Floating 在非 Android 平台空转', () {
    test('所有方法返回默认值且不调用 dsh/floating 通道', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('dsh/floating');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(await Floating.isRunning(), isFalse);
      expect(await Floating.canDrawOverlay(), isFalse);
      await Floating.start();
      await Floating.stop();
      await Floating.openOverlaySettings();
      await Floating.notifyBalance(12.5);
      await Floating.setBalanceAlert(true, 10);
      expect(await Floating.consumeOpenPanel(), isNull);

      expect(
        calls,
        isEmpty,
        reason: 'iOS/测试宿主绝不能向未注册的 dsh/floating 原生通道发请求',
      );
    });

    test('store.restoreFloating 在偏好为开时也不触达通道', () async {
      SharedPreferences.setMockInitialValues({'dsh_mr_floating': true});
      final store = AppStore();
      await store.loadPrefs();
      expect(store.floatingEnabled, isTrue);

      await store.restoreFloating();
      await store.setBalanceAlert(true);
      await store.setBalanceThreshold(20);
      expect(store.balanceAlert, isTrue);
      expect(store.balanceThreshold, 20);
    });
  });

  group('dsh/files 通道失败 → 本地化提示', () {
    const channel = MethodChannel('dsh/files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void mock(Future<Object?> Function(MethodCall) handler) {
      messenger.setMockMethodCallHandler(channel, handler);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    test('原生未注册（MissingPluginException）→ FilesChannelError', () async {
      mock((call) async => throw MissingPluginException('no native'));
      await expectLater(
        FilesChannel.pickFile(),
        throwsA(
          isA<FilesChannelError>().having(
            (e) => e.message,
            'message',
            contains('暂不支持文件操作'),
          ),
        ),
      );
      await expectLater(
        FilesChannel.saveToDownloads(
          name: 'a.txt',
          bytes: Uint8List.fromList([1]),
        ),
        throwsA(isA<FilesChannelError>()),
      );
    });

    test('原生 PlatformException → 可读文案（权限引导）', () async {
      mock(
        (call) async => throw PlatformException(
          code: 'PERMISSION_DENIED',
          message: 'no access',
        ),
      );
      await expectLater(
        FilesChannel.pickFile(),
        throwsA(
          isA<FilesChannelError>().having(
            (e) => e.message,
            'message',
            contains('权限'),
          ),
        ),
      );
    });

    test('原生已知错误码 → 本地化文案（不透出英文技术细节）', () async {
      mock(
        (call) async => throw PlatformException(
          code: 'read-failed',
          message: 'NSFileReadNoPermissionError',
        ),
      );
      await expectLater(
        FilesChannel.pickFile(),
        throwsA(
          isA<FilesChannelError>().having((e) => e.message, 'message', '读取文件失败'),
        ),
      );

      mock(
        (call) async =>
            throw PlatformException(code: 'save-failed', message: 'disk full'),
      );
      await expectLater(
        FilesChannel.saveToDownloads(
          name: 'a.txt',
          bytes: Uint8List.fromList([1]),
        ),
        throwsA(
          isA<FilesChannelError>().having((e) => e.message, 'message', '保存文件失败'),
        ),
      );

      mock(
        (call) async =>
            throw PlatformException(code: 'busy', message: 'already picking'),
      );
      await expectLater(
        FilesChannel.pickFile(),
        throwsA(
          isA<FilesChannelError>().having(
            (e) => e.message,
            'message',
            contains('已打开'),
          ),
        ),
      );
    });

    test('pickFile 成功返回名称与字节，空字节报读取失败', () async {
      mock(
        (call) async => {
          'name': 'note.txt',
          'bytes': Uint8List.fromList([1, 2, 3]),
        },
      );
      final picked = await FilesChannel.pickFile();
      expect(picked, isNotNull);
      expect(picked!.name, 'note.txt');
      expect(picked.bytes, [1, 2, 3]);

      mock((call) async => {'name': 'empty.txt', 'bytes': Uint8List(0)});
      await expectLater(
        FilesChannel.pickFile(),
        throwsA(
          isA<FilesChannelError>().having(
            (e) => e.message,
            'message',
            contains('读取文件失败'),
          ),
        ),
      );
    });

    test('保存成功文案：非 iOS 用完整路径，iOS 只显示文件名', () {
      expect(
        FilesChannel.savedMessage('/sdcard/Download/report.pdf', 'report.pdf'),
        contains('/sdcard/Download/report.pdf'),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final iosMessage = FilesChannel.savedMessage(
          '/var/mobile/Containers/Data/Application/UUID/Documents/report.pdf',
          'report.pdf',
        );
        expect(iosMessage, contains('「文件」App'));
        expect(iosMessage, contains('report.pdf'));
        expect(iosMessage, isNot(contains('var/mobile')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('页面转场', () {
    Future<void> pushSecondPage(WidgetTester tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: DshTheme.light(),
          navigatorKey: navKey,
          home: const Scaffold(body: Text('home')),
        ),
      );
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('next')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('iOS 用原生 Cupertino 转场（自带边缘右滑返回手势）', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pushSecondPage(tester);
        // 每条 route 都经 PageTransitionsTheme 包装：初始页 + 新页各一层
        // CupertinoPageTransition（只有它内部挂 _CupertinoBackGestureDetector 边缘手势）。
        expect(find.byType(CupertinoPageTransition), findsWidgets);
        await tester.pumpAndSettle();
      });
    });

    testWidgets('Android 保留自定义转场（未切换到 Cupertino）', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        await pushSecondPage(tester);
        expect(find.byType(CupertinoPageTransition), findsNothing);
        await tester.pumpAndSettle();
      });
    });
  });

  group('iOS 状态栏样式', () {
    testWidgets('iOS 深色主题 → 浅色状态栏文字', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        Widget? wrapped;
        await tester.pumpWidget(
          MaterialApp(
            theme: DshTheme.dark(),
            home: Builder(
              builder: (context) {
                wrapped = DshTheme.withIosStatusBar(
                  context,
                  const SizedBox.shrink(),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(wrapped, isA<AnnotatedRegion<SystemUiOverlayStyle>>());
        final style = (wrapped! as AnnotatedRegion<SystemUiOverlayStyle>).value;
        expect(style.statusBarBrightness, Brightness.dark);
      });
    });

    testWidgets('非 iOS 原样返回 child（Android 行为不变）', (tester) async {
      Widget? wrapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: DshTheme.dark(),
          home: Builder(
            builder: (context) {
              wrapped = DshTheme.withIosStatusBar(
                context,
                const SizedBox.shrink(),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(wrapped, isA<SizedBox>());
    });
  });

  group('设置页悬浮球入口', () {
    Future<void> pumpSettings(WidgetTester tester, AppStore store) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(store: store, onReconfigure: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('iOS 隐藏悬浮球开关与说明入口', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        final store = AppStore();
        await store.loadPrefs();
        await pumpSettings(tester, store);
        await tester.scrollUntilVisible(
          find.byIcon(Icons.language_outlined),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('悬浮球'), findsNothing);
        expect(find.text('悬浮球操作说明'), findsNothing);
      });
    });

    testWidgets('非 iOS 宿主保留悬浮球入口（Android 行为不变）', (tester) async {
      final store = AppStore();
      await store.loadPrefs();
      await pumpSettings(tester, store);
      await tester.scrollUntilVisible(
        find.byIcon(Icons.bubble_chart_outlined),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('悬浮球'), findsOneWidget);
      expect(find.text('悬浮球操作说明'), findsOneWidget);
    });
  });
}
