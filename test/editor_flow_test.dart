import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/app_theme.dart';
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/edit_selection.dart';
import 'package:ringtone_maker/export_options.dart';
import 'package:ringtone_maker/widgets/save_ringtone_dialog.dart';
import 'package:ringtone_maker/widgets/recorder_waveforms.dart';
import 'package:ringtone_maker/widgets/recorder_action_icon.dart';
import 'editor_page_test.dart' show TestPlayer;

void main() {
  const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
  final calls = <MethodCall>[];
  Completer<String>? pendingPreview;
  late Completer<void> previewReleased;
  setUp(() {
    calls.clear();
    pendingPreview = null;
    previewReleased = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'waveform') return List<double>.filled(1000, .4);
          if (call.method == 'preview') {
            return pendingPreview?.future ?? '/tmp/preview_test.m4a';
          }
          if (call.method == 'export') {
            throw PlatformException(
              code: 'TEST',
              message: 'test export capture',
            );
          }
          if (call.method == 'releasePreview' && !previewReleased.isCompleted) {
            previewReleased.complete();
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> startLoop(WidgetTester tester, TestPlayer player) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: EditorPage(filePath: '/test.wav', isVideo: false, player: player),
      ),
    );
    await tester.pumpAndSettle();
    final wave = tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
    wave.onInteractionStart();
    wave.onStart(10000);
    wave.onEnd(20000);
    wave.onInteractionEnd();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.repeat_rounded)).color,
      const Color(0xFF777A7D),
    );
    await tester.tap(find.byKey(const ValueKey('loop-selection')));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.repeat_rounded)).color,
      editorBlue,
    );
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> holdLoopSeek(WidgetTester tester, TestPlayer player) async {
    player.seekGate = Completer<void>();
    player.positions.add(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(player.lastSeek, const Duration(seconds: 10));
  }

  testWidgets(
    'loop rewind keeps editing controls enabled and their colors stable',
    (tester) async {
      final player = TestPlayer();
      await startLoop(tester, player);
      for (var cycle = 0; cycle < 3; cycle++) {
        await holdLoopSeek(tester, player);
        final icons = tester.widgetList<RecorderActionIcon>(
          find.byType(RecorderActionIcon),
        );
        expect(icons, hasLength(2));
        for (final icon in icons) {
          expect(icon.color, Colors.black);
          expect(icon.background, Colors.white);
        }
        for (final label in ['移除', '保留']) {
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byType(InkWell),
          );
          expect(tester.widget<InkWell>(button).onTap, isNotNull);
        }
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
              .onPressed,
          isNotNull,
        );
        expect(
          tester.widget<DetailWaveform>(find.byType(DetailWaveform)).enabled,
          isTrue,
        );
        player.seekGate!.complete();
        await tester.pumpAndSettle();
        player.seekGate = null;
        expect(player.started, isTrue);
      }
      expect(player.loads, 1, reason: 'looping must never reload the source');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final action in ['移除', '保留']) {
    testWidgets(
      '$action during a loop rewind waits for seek and never restarts old audio',
      (tester) async {
        final player = TestPlayer();
        await startLoop(tester, player);
        await holdLoopSeek(tester, player);
        final plays = player.playCount;
        await tester.tap(find.text(action));
        await tester.pump();
        expect(find.text('正在更新音频…'), findsOneWidget);
        expect(
          player.loads,
          1,
          reason: 'finish the old seek before loading the edited timeline',
        );
        player.seekGate!.complete();
        await tester.pumpAndSettle();
        player.seekGate = null;
        final wave = tester.widget<OverviewWaveform>(
          find.byType(OverviewWaveform),
        );
        expect(wave.timeline.durationMs, action == '移除' ? 50000 : 10000);
        expect(
          wave.timeline.spans.map((s) => [s.startMs, s.endMs]),
          action == '移除'
              ? [
                  [0, 10000],
                  [20000, 60000],
                ]
              : [
                  [10000, 20000],
                ],
        );
        expect(player.started, isFalse);
        expect(player.playCount, plays);
        await tester.tap(find.byTooltip('撤销上次编辑'));
        await tester.pumpAndSettle();
        final restored = tester.widget<OverviewWaveform>(
          find.byType(OverviewWaveform),
        );
        expect(restored.timeline.durationMs, 60000);
        expect(restored.startMs, 10000);
        expect(restored.endMs, 20000);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'pausing during loop seek wins and its pending transition stays locked',
    (tester) async {
      final player = TestPlayer();
      await startLoop(tester, player);
      await holdLoopSeek(tester, player);
      final plays = player.playCount;
      player.pauseGate = Completer<void>();
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(player.started, isFalse);
      player.seekGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(player.playCount, plays);
      expect(
        tester.widget<DetailWaveform>(find.byType(DetailWaveform)).enabled,
        isFalse,
        reason: 'loop completion must not unlock a pending user pause',
      );
      player.pauseGate!.complete();
      await tester.pumpAndSettle();
      player.seekGate = null;
      player.pauseGate = null;
      expect(player.started, isFalse);
      expect(
        tester.widget<DetailWaveform>(find.byType(DetailWaveform)).enabled,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'upper boundary drag during loop rewind resumes only after release',
    (tester) async {
      final player = TestPlayer();
      await startLoop(tester, player);
      await holdLoopSeek(tester, player);
      final plays = player.playCount;
      DetailWaveform wave() =>
          tester.widget<DetailWaveform>(find.byType(DetailWaveform));
      wave().onBoundaryDragStart!(1);
      wave().onEnd(18000);
      await tester.pump();
      expect(player.started, isFalse);
      player.seekGate!.complete();
      await tester.pumpAndSettle();
      player.seekGate = null;
      expect(player.started, isFalse);
      expect(player.playCount, plays);
      expect(wave().activeBoundary, 1);
      wave().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(player.started, isTrue);
      expect(player.playCount, plays + 1);
      expect(wave().endMs, 18000);
      expect(wave().positionMs, 10000);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'long press during loop rewind pauses and keeps the marker menu stable',
    (tester) async {
      final player = TestPlayer();
      await startLoop(tester, player);
      await holdLoopSeek(tester, player);
      final plays = player.playCount;
      final box = tester.getRect(find.byType(DetailWaveform));
      await tester.longPressAt(Offset(box.left + 70, box.center.dy));
      await tester.pumpAndSettle();
      expect(player.started, isFalse);
      expect(find.text('当前播放位置 00:10.00'), findsOneWidget);
      player.seekGate!.complete();
      await tester.pumpAndSettle();
      player.seekGate = null;
      expect(player.playCount, plays);
      expect(player.started, isFalse);
      expect(find.text('当前播放位置 00:10.00'), findsOneWidget);
      await tester.tapAt(const Offset(10, 760));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('loop-selection')));
      await tester.pump();
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat_rounded)).color,
        const Color(0xFF777A7D),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'loop repeats selection, ending audition stops, precise input validates and redo restores',
    (tester) async {
      phone(tester);
      final player = TestPlayer();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: EditorPage(
            filePath: '/test.wav',
            isVideo: false,
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      OverviewWaveform wave() =>
          tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
      wave().onInteractionStart();
      wave().onStart(10000);
      wave().onEnd(20000);
      wave().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(find.text('已选 10 秒'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('loop-selection')));
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      player.positions.add(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 10));
      expect(player.started, isTrue);
      await tester.tap(find.byKey(const ValueKey('audition-ending')));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 18));
      player.positions.add(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(player.started, isFalse);
      await tester.tap(find.byKey(const ValueKey('adjust-start')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('boundary-time')), '21');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入 0:00.000'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('boundary-time')),
        '12.5',
      );
      await tester.tap(find.text('+ 0.05 秒'));
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(wave().startMs, 12550);
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(wave().timeline.durationMs, 7450);
      await tester.tap(find.byTooltip('撤销上次编辑'));
      await tester.pumpAndSettle();
      expect(wave().timeline.durationMs, 60000);
      await tester.tap(find.byTooltip('重做上次编辑'));
      await tester.pumpAndSettle();
      expect(wave().timeline.durationMs, 7450);
      await tester.tap(find.byTooltip('撤销上次编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重做上次编辑'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  Future<void> showSave(
    WidgetTester tester,
    void Function(SaveRingtoneOptions?) result, {
    TestPlayer? player,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<SaveRingtoneOptions>(
                  context: context,
                  builder: (_) => SaveRingtoneDialog(
                    path: '/test.wav',
                    name: 'example',
                    timeline: AudioTimeline.full(60000),
                    selection: EditSelection.full(
                      60000,
                    ).withStart(10000).withEnd(20000),
                    createPlayer: player == null ? null : () => player,
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
  }

  testWidgets(
    'save defaults to selection and independent fades remain explicitly optional',
    (tester) async {
      SaveRingtoneOptions? options;
      await showSave(tester, (v) => options = v);
      expect(
        tester
            .widget<RadioGroup<bool>>(find.byType(RadioGroup<bool>))
            .groupValue,
        isTrue,
      );
      await tester.tap(find.text('声音选项'));
      await tester.pumpAndSettle();
      SwitchListTile control(String key) =>
          tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));
      expect(control('fade-in-switch').value, isFalse);
      expect(control('fade-out-switch').value, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('fade-in-switch')));
      await tester.tap(find.byKey(const ValueKey('fade-in-switch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('in-500')));
      await tester.tap(find.byKey(const ValueKey('in-500')));
      await tester.pumpAndSettle();
      expect(control('fade-out-switch').value, isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('fade-out-switch')));
      await tester.tap(find.byKey(const ValueKey('fade-out-switch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('out-1000')));
      await tester.tap(find.byKey(const ValueKey('out-1000')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('fade-in-switch')));
      await tester.tap(find.byKey(const ValueKey('fade-in-switch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('全部编辑结果'));
      await tester.tap(find.text('全部编辑结果'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(options!.selectionOnly, isFalse);
      expect(options!.fadeInMs, 0);
      expect(options!.fadeOutMs, 1000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor sends selected joined ranges and allows retry with full content',
    (tester) async {
      phone(tester);
      final player = TestPlayer();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: EditorPage(
            filePath: '/test.wav',
            isVideo: false,
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      OverviewWaveform wave() =>
          tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
      void select(int a, int b) {
        wave().onInteractionStart();
        wave().onStart(a);
        wave().onEnd(b);
        wave().onInteractionEnd();
      }

      select(20000, 40000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      select(15000, 25000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      final selected =
          calls.lastWhere((c) => c.method == 'export').arguments as Map;
      expect(selected['ranges'], [
        {'startUs': 15000000, 'endUs': 20000000},
        {'startUs': 40000000, 'endUs': 45000000},
      ]);
      expect(selected['fadeInMs'], 0);
      expect(selected['fadeOutMs'], 0);
      expect(wave().timeline.durationMs, 40000);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部编辑结果'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      final all = calls.lastWhere((c) => c.method == 'export').arguments as Map;
      expect(all['ranges'], [
        {'startUs': 0, 'endUs': 20000000},
        {'startUs': 40000000, 'endUs': 60000000},
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'effect preview renders selected endpoint and releases playback on cancel',
    (tester) async {
      final player = TestPlayer();
      await showSave(tester, (_) {}, player: player);
      await tester.tap(find.byKey(const ValueKey('preview-tail')));
      await tester.pumpAndSettle();
      final preview =
          calls.singleWhere((c) => c.method == 'preview').arguments as Map;
      expect(preview['ranges'], [
        {'startUs': 17000000, 'endUs': 20000000},
      ]);
      expect(preview['fadeInMs'], 0);
      expect(preview['fadeOutMs'], 0);
      expect(player.started, isTrue);
      // Start stream teardown in the real async zone too. Running only the
      // wait there leaves earlier fake-zone pause/cancel continuations stalled.
      await tester.runAsync(() async {
        await tester.tap(find.text('取消'));
        await previewReleased.future.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'releasePreview'), hasLength(1));
      expect(player.states.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing while rendering never starts a late preview', (
    tester,
  ) async {
    final player = TestPlayer();
    pendingPreview = Completer<String>();
    await showSave(tester, (_) {}, player: player);
    await tester.tap(find.byKey(const ValueKey('preview-head')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    pendingPreview!.complete('/tmp/preview_late.m4a');
    await tester.pumpAndSettle();
    expect(player.loads, 0);
    expect(player.started, isFalse);
    expect(calls.where((c) => c.method == 'releasePreview'), hasLength(1));
    await player.dispose();
    expect(tester.takeException(), isNull);
  });
}
