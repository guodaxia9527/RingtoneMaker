import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/widgets/recorder_waveforms.dart';

void main() {
  testWidgets('overview ignores middle touches but supports endpoint drags', (
    tester,
  ) async {
    int starts = 0, ends = 0, interactions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: OverviewWaveform(
              timeline: AudioTimeline.full(60000),
              peaks: const [.2, .8],
              startMs: 0,
              endMs: 60000,
              positionMs: 0,
              onStart: (v) => starts = v,
              onEnd: (v) => ends = v,
              onInteractionStart: () => interactions++,
              onInteractionEnd: () {},
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(OverviewWaveform));
    await tester.tapAt(origin + const Offset(180, 30));
    await tester.dragFrom(origin + const Offset(180, 30), const Offset(40, 0));
    expect(interactions, 0);
    await tester.dragFrom(origin + const Offset(16, 30), const Offset(40, 0));
    expect(starts, greaterThan(3000));
    expect(interactions, 1);
    await tester.dragFrom(origin + const Offset(344, 30), const Offset(-40, 0));
    expect(ends, lessThan(57000));
    expect(interactions, 2);
  });
  testWidgets(
    'detail moves waveform under fixed head and adjusts blue boundary',
    (tester) async {
      int? seek, boundary, window;
      var menus = 0, toggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 220,
              child: DetailWaveform(
                timeline: AudioTimeline.full(60000),
                peaks: const [.2, .8],
                startMs: 10000,
                endMs: 20000,
                positionMs: 15000,
                windowMs: 20000,
                onStart: (v) => boundary = v,
                onEnd: (_) {},
                onSeek: (v) => seek = v,
                onZoom: (v) => window = v,
                onInteractionStart: () {},
                onInteractionEnd: () {},
                onPositionMenuRequested: (_) => menus++,
                onTogglePlayback: () => toggles++,
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(DetailWaveform));
      await tester.tapAt(origin + const Offset(180, 100));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(origin + const Offset(180, 100));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(menus, 0);
      await tester.longPressAt(origin + const Offset(180, 100));
      await tester.pumpAndSettle();
      expect(menus, 1);
      expect(toggles, 1);
      expect(seek, isNull);
      expect(boundary, isNull);
      await tester.dragFrom(
        origin + const Offset(180, 100),
        const Offset(54, 0),
      );
      expect(seek, closeTo(12000, 10));
      await tester.dragFrom(
        origin + const Offset(90, 100),
        const Offset(36, 0),
      );
      expect(boundary, closeTo(12000, 10));
      final left = await tester.startGesture(
        origin + const Offset(140, 100),
        pointer: 6,
      );
      final right = await tester.startGesture(
        origin + const Offset(220, 100),
        pointer: 7,
      );
      await left.moveTo(origin + const Offset(110, 100));
      await right.moveTo(origin + const Offset(250, 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(window, isNotNull);
      expect(window, lessThan(20000));
      expect(menus, 1, reason: 'drags and pinches must not open the menu');
      expect(toggles, 1, reason: 'drags and pinches must not toggle playback');
      await left.up();
      await right.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('overview caps meet the blue outer border without a gap', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 360,
                height: 66,
                child: OverviewWaveform(
                  timeline: AudioTimeline.full(60000),
                  peaks: const [.2, .8],
                  startMs: 10000,
                  endMs: 50000,
                  positionMs: 30000,
                  onStart: (_) {},
                  onEnd: (_) {},
                  onInteractionStart: () {},
                  onInteractionEnd: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final colors = await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = <List<int>>[];
      for (final x in [60, 300]) {
        final i = (33 * image.width + x) * 4;
        pixels.add([
          data!.getUint8(i),
          data.getUint8(i + 1),
          data.getUint8(i + 2),
        ]);
      }
      image.dispose();
      return pixels;
    });
    expect(colors, [
      [8, 126, 255],
      [8, 126, 255],
    ]);
  });

  testWidgets(
    'overview grip drag preserves grab offset and the shared time axis',
    (tester) async {
      int? start, end;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 360,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: OverviewWaveform(
                  timeline: AudioTimeline.full(60000),
                  peaks: const [.2, .8],
                  startMs: 0,
                  endMs: 60000,
                  positionMs: 0,
                  onStart: (v) => start = v,
                  onEnd: (v) => end = v,
                  onInteractionStart: () {},
                  onInteractionEnd: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(OverviewWaveform));
      for (final grabX in [4.0, 13.5, 22.0]) {
        await tester.dragFrom(origin + Offset(grabX, 30), const Offset(31, 0));
        expect(
          start,
          6000,
          reason: 'the finger may grab anywhere on the left grip',
        );
      }
      for (final grabX in [338.0, 346.5, 356.0]) {
        await tester.dragFrom(origin + Offset(grabX, 30), const Offset(-31, 0));
        expect(end, 54000, reason: 'the right grip uses the same time scale');
      }
    },
  );

  testWidgets('overview playhead meets the inner grip edge at either boundary', (
    tester,
  ) async {
    for (final range in [
      [0, 60000],
      [10000, 50000],
    ]) {
      for (final atStart in [true, false]) {
        final key = GlobalKey();
        final position = atStart ? range[0] : range[1];
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 360,
                  height: 66,
                  child: OverviewWaveform(
                    timeline: AudioTimeline.full(60000),
                    peaks: const [0.0],
                    startMs: range[0],
                    endMs: range[1],
                    positionMs: position,
                    onStart: (_) {},
                    onEnd: (_) {},
                    onInteractionStart: () {},
                    onInteractionEnd: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pixels = await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final headX = (25 + position / 60000 * 310).floor();
          final colors = <Color>[];
          for (final dx in [-3, 0, 3]) {
            final index = (20 * image.width + headX + dx) * 4;
            colors.add(
              Color.fromARGB(
                255,
                data.getUint8(index),
                data.getUint8(index + 1),
                data.getUint8(index + 2),
              ),
            );
          }
          image.dispose();
          return colors;
        });
        expect(pixels![1], editorGreen);
        expect(pixels[atStart ? 0 : 2], editorBlue);
        expect(
          pixels[atStart ? 2 : 0],
          isNot(editorBlue),
          reason:
              'the playhead must border waveform content, not sit inside the grip',
        );
      }
    }
  });
}
