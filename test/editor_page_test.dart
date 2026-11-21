import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ringtone_maker/app_theme.dart' show buildAppTheme;
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/widgets/recorder_waveforms.dart';

class TestPlayer extends Fake implements AudioPlayer {
  final positions = StreamController<Duration>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  final events = StreamController<PlaybackEvent>.broadcast();
  Duration? lastSeek;
  AudioSource? source;
  int index = 0, pauseCount = 0, playCount = 0, loads = 0;
  bool started = false;
  Completer<void>? pauseGate, seekGate;
  @override
  int? get currentIndex => index;
  @override
  bool get playing => started;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Duration? get duration => const Duration(seconds: 60);
  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) => setFilePath(url, initialPosition: initialPosition);
  @override
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loads++;
    index = 0;
    lastSeek = initialPosition;
    return const Duration(seconds: 60);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loads++;
    source = audioSource;
    index = initialIndex ?? 0;
    lastSeek = initialPosition;
    return const Duration(seconds: 60);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    lastSeek = position;
    this.index = index ?? this.index;
    await seekGate?.future;
  }

  @override
  Future<void> pause() async {
    started = false;
    pauseCount++;
    states.add(PlayerState(false, ProcessingState.ready));
    await pauseGate?.future;
  }

  @override
  Future<void> play() async {
    playCount++;
    started = true;
    states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> dispose() async {
    await positions.close();
    await states.close();
    await events.close();
  }
}

Future<void> loadPreviewFonts(WidgetTester tester) async {
  final fontPath = Platform.environment['RINGTONE_PREVIEW_FONT'];
  final iconPath = Platform.environment['RINGTONE_PREVIEW_ICONS'];
  if (fontPath == null) return;
  await tester.runAsync(() async {
    final bytes = await File(fontPath).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    if (iconPath != null) {
      final bytes = await File(iconPath).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
}

void main() {
  const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'waveform') {
            return List.generate(
              3000,
              (i) =>
                  (.2 + math.sin(i * .09).abs() * .8) * math.sin(i * .2).abs(),
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'scrubbing stays live, upper boundaries pause then resume, and reference marks clear',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts(tester);
      final player = TestPlayer(), boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: EditorPage(
              filePath: '/test/录音示例.wav',
              isVideo: false,
              player: player,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      DetailWaveform detail() =>
          tester.widget<DetailWaveform>(find.byType(DetailWaveform));
      OverviewWaveform overview() =>
          tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
      final preview = Platform.environment['RINGTONE_PREVIEW_PATH'];
      if (preview != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      overview().onInteractionStart();
      overview().onStart(10000);
      overview().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(detail().positionMs, 10000);
      expect(detail().startMs, 10000);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(player.started, isTrue);
      expect(detail().playOriginMs, 10000);
      final pauses = player.pauseCount;
      detail().onInteractionStart();
      detail().onSeek(15000);
      await tester.pumpAndSettle();
      expect(detail().dragOriginMs, 10000);
      expect(detail().positionMs, 15000);
      expect(overview().positionMs, 15000);
      detail().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(detail().dragOriginMs, isNull);
      expect(detail().playOriginMs, 10000);
      expect(player.pauseCount, pauses);
      player.pauseGate = Completer<void>();
      detail().onBoundaryDragStart!(1);
      detail().onEnd(17000);
      await tester.pumpAndSettle();
      expect(player.started, isFalse);
      expect(detail().activeBoundary, 1);
      final detailBox = tester.getRect(find.byType(DetailWaveform));
      final draggedColor = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final index =
            ((detailBox.top + 64).round() * image.width +
                (detailBox.center.dx +
                        (17000 - 15000) / detail().windowMs * detailBox.width)
                    .round()) *
            4;
        final color = [
          bytes!.getUint8(index),
          bytes.getUint8(index + 1),
          bytes.getUint8(index + 2),
        ];
        image.dispose();
        return color;
      });
      expect(
        draggedColor![0],
        greaterThan(draggedColor[1] + 60),
        reason: 'the dragged boundary is red while the playhead stays in place',
      );
      expect(detail().positionMs, 15000);
      expect(overview().endMs, 17000);
      detail().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(
        player.started,
        isFalse,
        reason: 'release must wait for the native pause acknowledgment',
      );
      player.pauseGate!.complete();
      await tester.pumpAndSettle();
      player.pauseGate = null;
      expect(detail().activeBoundary, isNull);
      expect(detail().positionMs, 15000);
      expect(player.lastSeek, const Duration(seconds: 15));
      expect(player.pauseCount, pauses + 1);
      expect(
        player.loads,
        1,
        reason: 'scrubbing and trimming must never reload audio',
      );
      expect(player.started, isTrue);
      player.positions.add(const Duration(seconds: 45));
      await tester.pumpAndSettle();
      expect(player.started, isFalse);
      expect(detail().playOriginMs, isNull);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 10));
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      detail().onBoundaryDragStart!(0);
      detail().onStart(12000);
      await tester.pumpAndSettle();
      expect(detail().positionMs, 10000);
      expect(player.started, isFalse);
      detail().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(
        player.started,
        isFalse,
        reason: 'dragging while paused must not start playback',
      );
      expect(detail().activeBoundary, isNull);
      // Lower grips always carry the head, even with stale playback events.
      overview().onInteractionStart();
      overview().onStart(13000);
      player.positions.add(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(detail().positionMs, 13000);
      overview().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(detail().positionMs, 13000);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      overview().onInteractionStart();
      overview().onEnd(16000);
      player.positions.add(const Duration(seconds: 14));
      await tester.pumpAndSettle();
      expect(detail().positionMs, 16000);
      overview().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(detail().positionMs, 16000);
      expect(player.lastSeek, const Duration(seconds: 16));
      expect(player.started, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('remove, extract and undo keep editable source intervals', (
    tester,
  ) async {
    final player = TestPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          filePath: '/test/example.wav',
          isVideo: false,
          player: player,
        ),
      ),
    );
    await tester.pumpAndSettle();
    OverviewWaveform overview() =>
        tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
    void select(int start, int end) {
      overview().onInteractionStart();
      overview().onStart(start);
      overview().onEnd(end);
      overview().onInteractionEnd();
    }

    select(20000, 40000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('移除'));
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(overview().timeline.durationMs, 40000);
    expect(overview().timeline.spans.map((s) => [s.startMs, s.endMs]), [
      [0, 20000],
      [40000, 60000],
    ]);
    expect(player.source, isA<ConcatenatingAudioSource>());
    select(10000, 30000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保留'));
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect(overview().timeline.durationMs, 20000);
    expect(overview().timeline.spans.map((s) => [s.startMs, s.endMs]), [
      [10000, 20000],
      [40000, 50000],
    ]);
    await tester.tap(find.byTooltip('撤销上次编辑'));
    await tester.pumpAndSettle();
    expect(overview().timeline.durationMs, 40000);
    await tester.tap(find.byTooltip('撤销上次编辑'));
    await tester.pumpAndSettle();
    expect(overview().timeline.durationMs, 60000);
    expect(overview().startMs, 20000);
    expect(overview().endMs, 40000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'double tap toggles playback and long press pauses before offering fixed-position markers',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts(tester);
      final player = TestPlayer(), previewKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: EditorPage(
              filePath: '/test/example.wav',
              isVideo: false,
              player: player,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      DetailWaveform detail() =>
          tester.widget<DetailWaveform>(find.byType(DetailWaveform));
      OverviewWaveform overview() =>
          tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));
      Future<void> doubleTapWave() async {
        // Deliberately away from the centered head: taps must not change its time.
        final box = tester.getRect(find.byType(DetailWaveform));
        final point = Offset(box.left + 70, box.center.dy);
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }

      Future<void> longPressWave() async {
        final box = tester.getRect(find.byType(DetailWaveform));
        await tester.longPressAt(Offset(box.left + 70, box.center.dy));
        await tester.pumpAndSettle();
      }

      PopupMenuItem<bool> item(String name) =>
          tester.widget<PopupMenuItem<bool>>(
            find.byKey(ValueKey('mark-position-$name')),
          );

      detail().onSeek(15000);
      await tester.pumpAndSettle();
      await doubleTapWave();
      expect(player.started, isTrue);
      expect(detail().positionMs, 15000);
      expect(find.text('设置起点'), findsNothing);
      await doubleTapWave();
      expect(player.started, isFalse);
      expect(detail().positionMs, 15000);
      expect(find.text('设置起点'), findsNothing);
      await longPressWave();
      expect(find.text('当前播放位置 00:15.00'), findsOneWidget);
      expect(detail().positionMs, 15000);
      final preview = Platform.environment['RINGTONE_MARKER_PREVIEW_PATH'];
      if (preview != null) {
        await tester.runAsync(() async {
          final image =
              await (previewKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('设置起点'));
      await tester.pumpAndSettle();
      expect(detail().startMs, 15000);
      expect(overview().startMs, 15000);
      expect(detail().positionMs, 15000);
      expect(player.started, isFalse);

      detail().onSeek(25000);
      await tester.pumpAndSettle();
      await longPressWave();
      await tester.tap(find.text('设置终点'));
      await tester.pumpAndSettle();
      expect(detail().endMs, 25000);
      expect(overview().endMs, 25000);
      expect(detail().positionMs, 25000);

      // Outside the selection, only the boundary that can extend it is enabled.
      detail().onSeek(30000);
      await tester.pumpAndSettle();
      await longPressWave();
      expect(item('start').enabled, isFalse);
      expect(item('end').enabled, isTrue);
      await tester.tap(find.text('设置起点'));
      await tester.pumpAndSettle();
      expect(find.text('设置起点'), findsOneWidget);
      await tester.tapAt(const Offset(10, 760));
      await tester.pumpAndSettle();
      expect(detail().startMs, 15000);
      expect(detail().endMs, 25000);
      expect(detail().positionMs, 30000);

      detail().onSeek(15050);
      await tester.pumpAndSettle();
      await longPressWave();
      expect(
        item('end').enabled,
        isFalse,
        reason: 'keep at least 100 ms selected',
      );
      await tester.tapAt(const Offset(10, 760));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      final waveBox = tester.getRect(find.byType(DetailWaveform));
      await tester.tapAt(Offset(waveBox.left + 70, waveBox.center.dy));
      await tester.pump(const Duration(milliseconds: 350));
      expect(player.started, isTrue, reason: 'a single tap does not pause');
      player.positions.add(const Duration(milliseconds: 18420));
      await tester.pumpAndSettle();
      final pauses = player.pauseCount;
      final lastSeek = player.lastSeek;
      player.pauseGate = Completer<void>();
      await doubleTapWave();
      expect(find.text('设置起点'), findsNothing);
      expect(player.started, isFalse);
      expect(player.pauseCount, pauses + 1);
      expect(detail().positionMs, 18420);
      expect(overview().positionMs, 18420);
      expect(detail().playOriginMs, isNull);
      expect(
        player.lastSeek,
        lastSeek,
        reason: 'pause must not reposition the head',
      );
      expect(detail().startMs, 15000);
      expect(detail().endMs, 25000);

      await doubleTapWave();
      expect(
        find.text('设置起点'),
        findsNothing,
        reason: 'wait for native pause completion before accepting markers',
      );
      expect(player.pauseCount, pauses + 1);
      player.pauseGate!.complete();
      player.pauseGate = null;
      await tester.pumpAndSettle();
      expect(find.text('设置起点'), findsNothing);
      await doubleTapWave();
      expect(
        player.started,
        isTrue,
        reason: 'double tap resumes at the paused position',
      );
      expect(detail().positionMs, 18420);
      expect(find.text('设置起点'), findsNothing);
      player.pauseGate = Completer<void>();
      await longPressWave();
      expect(player.started, isFalse);
      expect(player.pauseCount, pauses + 2);
      expect(
        find.text('设置起点'),
        findsNothing,
        reason: 'long press must wait for native pause before opening the menu',
      );
      player.positions.add(const Duration(milliseconds: 19000));
      await tester.pumpAndSettle();
      expect(
        detail().positionMs,
        18420,
        reason: 'freeze the displayed position at long-press recognition',
      );
      player.pauseGate!.complete();
      player.pauseGate = null;
      await tester.pumpAndSettle();
      expect(find.text('当前播放位置 00:18.42'), findsOneWidget);
      expect(item('start').enabled, isTrue);
      expect(item('end').enabled, isTrue);
      expect(player.started, isFalse);
      player.positions.add(const Duration(milliseconds: 19500));
      await tester.pumpAndSettle();
      expect(detail().positionMs, 18420);
      expect(
        player.lastSeek,
        lastSeek,
        reason: 'long press pauses without seeking to the finger location',
      );
      await tester.tapAt(const Offset(10, 760));
      await tester.pumpAndSettle();
      expect(
        player.started,
        isFalse,
        reason: 'dismissing the menu leaves playback paused',
      );
      detail().onSeek(25000);
      await tester.pumpAndSettle();
      await doubleTapWave();
      expect(player.started, isTrue);
      expect(player.lastSeek, const Duration(seconds: 15));
      expect(
        detail().positionMs,
        15000,
        reason: 'double tap at the selection end restarts from its beginning',
      );
      expect(find.text('设置起点'), findsNothing);
      await doubleTapWave();
      expect(player.started, isFalse);
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(detail().timeline.durationMs, 10000);
      await tester.tap(find.byTooltip('撤销上次编辑'));
      await tester.pumpAndSettle();
      expect(detail().startMs, 15000);
      expect(detail().endMs, 25000);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
