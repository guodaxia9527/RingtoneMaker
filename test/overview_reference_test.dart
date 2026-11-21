import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/edit_selection.dart';
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/widgets/recorder_waveforms.dart';
import 'editor_page_test.dart' show TestPlayer;

void main() {
  const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
  final haptics = <Object?>[];
  setUp(() {
    haptics.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'waveform') return List<double>.filled(1000, .3);
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  OverviewWaveform wave(WidgetTester tester) =>
      tester.widget<OverviewWaveform>(find.byType(OverviewWaveform));

  Future<void> showOverview(
    WidgetTester tester, {
    int? reference = 30017,
    int position = 30017,
    int start = 0,
    int end = 60000,
    bool playing = false,
    GlobalKey? previewKey,
  }) async {
    final timeline = AudioTimeline.full(60000);
    var selection = EditSelection.full(60000).withStart(start).withEnd(end);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: previewKey,
              child: SizedBox(
                width: 360,
                height: 66,
                child: StatefulBuilder(
                  builder: (context, update) => OverviewWaveform(
                    timeline: timeline,
                    peaks: const [.15, .5, .2, .7, .1, .4],
                    startMs: selection.startMs,
                    endMs: selection.endMs,
                    positionMs: position,
                    referenceMs: reference,
                    playing: playing,
                    onStart: (value) => update(() {
                      selection = selection.withStart(value);
                      position = selection.startMs;
                    }),
                    onEnd: (value) => update(() {
                      selection = selection.withEnd(value);
                      position = selection.endMs;
                    }),
                    onInteractionStart: () {},
                    onInteractionEnd: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Point on the grip's center whose inner edge represents the given time.
  Offset gripAt(WidgetTester tester, int time, bool start, {double delta = 0}) {
    final box = tester.getRect(find.byType(OverviewWaveform));
    final px = 25 + time / wave(tester).timeline.durationMs * (box.width - 50);
    return box.topLeft + Offset(px + (start ? -11.5 : 11.5) + delta, 33);
  }

  for (final start in [true, false]) {
    testWidgets(
      '${start ? 'start' : 'end'} grip snaps exactly, tolerates jitter and can escape',
      (tester) async {
        await showOverview(tester);
        const target = 30017;
        final gesture = await tester.startGesture(
          gripAt(tester, start ? 0 : 60000, start),
        );
        await gesture.moveTo(gripAt(tester, target, start, delta: 4));
        await tester.pump();
        expect(start ? wave(tester).startMs : wave(tester).endMs, target);
        expect(wave(tester).positionMs, target);
        expect(haptics, ['HapticFeedbackType.selectionClick']);
        await gesture.moveTo(gripAt(tester, target, start, delta: 8));
        await tester.pump();
        expect(wave(tester).positionMs, target);
        expect(haptics, hasLength(1));
        await gesture.moveTo(gripAt(tester, target, start, delta: 15));
        await tester.pump();
        expect(wave(tester).positionMs, greaterThan(target));
        await gesture.moveTo(gripAt(tester, target, start, delta: 8));
        await tester.pump();
        expect(
          wave(tester).positionMs,
          isNot(target),
          reason: 'do not re-enter on minor edge jitter',
        );
        await gesture.moveTo(gripAt(tester, target, start, delta: 3));
        await tester.pump();
        expect(wave(tester).positionMs, target);
        expect(haptics, hasLength(2));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(wave(tester).referenceMs, target);
      },
    );

    testWidgets(
      '${start ? 'start' : 'end'} grip never snaps across the opposite boundary',
      (tester) async {
        final reference = start ? 40050 : 19950;
        await showOverview(
          tester,
          start: 20000,
          end: 40000,
          reference: reference,
        );
        final gesture = await tester.startGesture(
          gripAt(tester, start ? 20000 : 40000, start),
        );
        await gesture.moveTo(
          gripAt(tester, reference, start, delta: start ? -3 : 3),
        );
        await tester.pump();
        expect(wave(tester).positionMs, isNot(reference));
        expect(
          wave(tester).endMs - wave(tester).startMs,
          greaterThanOrEqualTo(100),
        );
        expect(haptics, isEmpty);
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('live playback does not create an invisible snap target', (
    tester,
  ) async {
    await showOverview(tester, reference: null, playing: true);
    final gesture = await tester.startGesture(gripAt(tester, 60000, false));
    await gesture.moveTo(gripAt(tester, 30017, false, delta: 4));
    await tester.pump();
    expect(wave(tester).endMs, isNot(30017));
    expect(haptics, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'paused target survives repeated drags, then clears on seek, play and content edits',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = TestPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            filePath: '/test.wav',
            isVideo: false,
            player: player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      DetailWaveform detail() =>
          tester.widget<DetailWaveform>(find.byType(DetailWaveform));
      Future<void> dragEndTo(int time, {double delta = 0}) async {
        final gesture = await tester.startGesture(
          gripAt(tester, wave(tester).endMs, false),
        );
        await gesture.moveTo(gripAt(tester, time, false, delta: delta));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      player.positions.add(const Duration(milliseconds: 30017));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      await dragEndTo(45000);
      expect(wave(tester).referenceMs, 30017);
      expect(detail().positionMs, closeTo(45000, 1));
      // A second drag must aim at the original heard position, not 45 seconds.
      await dragEndTo(30017, delta: 3);
      expect(wave(tester).endMs, 30017);
      expect(detail().positionMs, 30017);
      expect(wave(tester).referenceMs, 30017);
      expect(haptics, hasLength(1));
      detail().onBoundaryDragStart!(1);
      detail().onEnd(35000);
      detail().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(wave(tester).referenceMs, 30017);
      detail().onZoom(12000);
      await tester.pumpAndSettle();
      expect(wave(tester).referenceMs, 30017);
      detail().onInteractionStart();
      detail().onSeek(22000);
      detail().onInteractionEnd();
      await tester.pumpAndSettle();
      expect(wave(tester).referenceMs, isNull);
      await dragEndTo(40000);
      expect(wave(tester).referenceMs, 22000);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(wave(tester).referenceMs, isNull);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      wave(tester).onInteractionStart();
      wave(tester).onStart(10000);
      wave(tester).onInteractionEnd();
      await tester.pumpAndSettle();
      expect(wave(tester).referenceMs, isNotNull);
      await tester.tap(find.text('保留'));
      await tester.pumpAndSettle();
      expect(wave(tester).timeline.durationMs, 30000);
      expect(wave(tester).referenceMs, isNull);
      await tester.tap(find.byTooltip('撤销上次编辑'));
      await tester.pumpAndSettle();
      expect(wave(tester).timeline.durationMs, 60000);
      expect(wave(tester).referenceMs, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'fixed reference has a visible notch and dashed line apart from the green head',
    (tester) async {
      final previewKey = GlobalKey();
      await showOverview(
        tester,
        reference: 30000,
        position: 40000,
        start: 10000,
        end: 50000,
        previewKey: previewKey,
      );
      final colors = await tester.runAsync(() async {
        final image =
            await (previewKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        Color pixel(int x, int y) {
          final i = (y * image.width + x) * 4;
          return Color.fromARGB(
            255,
            bytes.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          );
        }

        final result = [
          pixel(360, 2),
          pixel(360, 18),
          pixel(360, 28),
          pixel(463, 18),
        ];
        final preview = Platform.environment['RINGTONE_REFERENCE_PREVIEW_PATH'];
        if (preview != null) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
        return result;
      });
      const referenceColor = Color(0xFF5F6B76);
      expect(colors![0], referenceColor);
      expect(colors[1], referenceColor);
      expect(
        colors[2],
        isNot(referenceColor),
        reason: 'a dashed gap distinguishes the reference',
      );
      expect(colors[3], editorGreen);
    },
  );
}
