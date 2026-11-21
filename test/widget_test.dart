import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/main.dart';

void main() {
  testWidgets('home exposes import and ringtone library', (tester) async {
    await tester.pumpWidget(const RingtoneApp());
    expect(find.text('选择文件'), findsOneWidget);
    expect(find.byTooltip('我的铃声'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('denied legacy storage permission keeps import recoverable', (
    tester,
  ) async {
    const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(const RingtoneApp());
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要存储权限'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '选择文件'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
