import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/app_theme.dart';
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/history_page.dart';
import 'package:ringtone_maker/widgets/saved_ringtone_sheet.dart';
import 'package:ringtone_maker/widgets/recorder_action_icon.dart';
import 'package:ringtone_maker/widgets/recorder_waveforms.dart';
import 'editor_page_test.dart' show TestPlayer;

void main() {
  const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'waveform') return List<double>.filled(1024, .4);
          if (call.method == 'queryRingtones') {
            return [
              {
                'uri': 'content://test/1',
                'name': 'example.m4a',
                'duration': 3000,
                'size': 100,
                'createdAt': 0,
              },
            ];
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('editing guards exit and enabled actions use black on white', (
    tester,
  ) async {
    final player = TestPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditorPage(
                    filePath: '/test.wav',
                    isVideo: false,
                    player: player,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final overview = tester.widget<OverviewWaveform>(
      find.byType(OverviewWaveform),
    );
    overview.onInteractionStart();
    overview.onStart(10000);
    overview.onInteractionEnd();
    await tester.pumpAndSettle();
    for (final icon in tester.widgetList<RecorderActionIcon>(
      find.byType(RecorderActionIcon),
    )) {
      expect(icon.color, Colors.black);
      expect(icon.background, Colors.white);
    }
    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '保存'),
    );
    expect(save.style!.foregroundColor!.resolve({}), Colors.black);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存铃声'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.ensureVisible(find.text('保留'));
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('还有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(EditorPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save completion waits for explicit preview', (tester) async {
    final player = TestPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SavedRingtoneSheet(
            uri: 'content://test/1',
            name: 'example.m4a',
            durationMs: 3000,
            player: player,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(player.started, isFalse);
    expect(player.loads, 0);
    await tester.tap(find.text('试听'));
    await tester.pumpAndSettle();
    expect(player.started, isTrue);
    expect(player.loads, 1);
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    expect(player.started, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('library loads without automatically playing', (tester) async {
    final player = TestPlayer();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HistoryPage(player: player, highlightUri: 'content://test/1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('example.m4a'), findsOneWidget);
    expect(player.loads, 0);
    expect(player.started, isFalse);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(player.started, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
