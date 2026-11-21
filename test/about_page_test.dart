import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/about_page.dart';
import 'package:ringtone_maker/app_theme.dart';
import 'package:ringtone_maker/main.dart';
import 'package:ringtone_maker/services/app_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var allowed = true;
  Future<Object?> Function()? save;

  setUp(() {
    calls.clear();
    allowed = true;
    save = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'appInfo':
          return {'versionName': '2.3.4', 'buildNumber': '42'};
        case 'ensureStoragePermission':
          return allowed;
        case 'saveSupportQr':
          return await save?.call() ?? 'content://media/images/7';
        default:
          throw StateError('Unexpected call: ${call.method}');
      }
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openSupport(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const AboutPage()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('请作者喝杯茶'));
    await tester.tap(find.text('请作者喝杯茶'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'home opens About and copies exact WeChat ID without permission',
    (tester) async {
      String? clipboard;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await tester.pumpWidget(const RingtoneApp());
      await tester.tap(find.byTooltip('关于'));
      await tester.pumpAndSettle();
      expect(find.text('版本 2.3.4（42）'), findsOneWidget);
      await tester.ensureVisible(find.text('复制'));
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(clipboard, 'GuoDaXia_Tools');
      expect(find.text('微信号已复制'), findsOneWidget);
      expect(calls.map((c) => c.method), ['appInfo']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('选择文件'), findsOneWidget);
    },
  );

  testWidgets(
    'save recovers from denial and failure, preserves original bytes',
    (tester) async {
      allowed = false;
      await openSupport(tester);
      expect(calls.map((c) => c.method), ['appInfo']);
      await tester.tap(find.text('保存到相册'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请授权后重试'), findsOneWidget);
      expect(calls.where((c) => c.method == 'saveSupportQr'), isEmpty);

      allowed = true;
      save = () async => throw PlatformException(code: 'SAVE_IMAGE_FAILED');
      await tester.tap(find.text('保存到相册'));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试'), findsOneWidget);

      final pending = Completer<Object?>();
      save = () => pending.future;
      await tester.tap(find.text('保存到相册'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('正在保存…'), findsOneWidget);
      await tester.tap(find.text('正在保存…'));
      await tester.pump();
      expect(calls.where((c) => c.method == 'saveSupportQr'), hasLength(2));
      final submitted = (calls.last.arguments as Map)['bytes'] as Uint8List;
      final original = await rootBundle.load(AppInfoService.supportQrAsset);
      expect(
        submitted,
        orderedEquals(
          original.buffer.asUint8List(
            original.offsetInBytes,
            original.lengthInBytes,
          ),
        ),
      );
      pending.complete('content://media/images/7');
      await tester.pumpAndSettle();
      expect(find.text('已保存到相册'), findsOneWidget);
      expect(find.text('保存失败，请重试'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dismissing support while saving finishes safely', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    save = () => pending.future;
    await openSupport(tester);
    await tester.tap(find.text('保存到相册'));
    await tester.pump();
    final context = tester.element(find.text('支持作者'));
    Navigator.pop(context);
    await tester.pumpAndSettle();
    pending.complete('content://media/images/7');
    await tester.pumpAndSettle();
    expect(find.text('支持作者'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small screen and large text keep support and licenses reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const AboutPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('请作者喝杯茶'));
      await tester.tap(find.text('请作者喝杯茶'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存到相册'));
      expect(tester.takeException(), isNull);
      Navigator.pop(tester.element(find.text('支持作者')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开源许可'));
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
