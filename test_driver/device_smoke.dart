import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/services/audio_service.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<File> fixture() async {
  const rate = 44100, seconds = 6;
  final bytes = ByteData(44 + rate * seconds * 2);
  void text(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, rate * seconds * 2, Endian.little);
  for (var i = 0; i < rate * seconds; i++) {
    final section = i ~/ (rate * 2);
    final amplitude = [.2, .9, .5][section], hz = [440, 880, 1320][section];
    bytes.setInt16(
      44 + i * 2,
      (math.sin(i * 2 * math.pi * hz / rate) * 30000 * amplitude).round(),
      Endian.little,
    );
  }
  final file = File('${(await getTemporaryDirectory()).path}/裁切交互测试.wav');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('正在验证裁切和拼接…'))),
    ),
  );
  final service = AudioService();
  final uris = <String>[];
  final copies = <File>[];
  try {
    final file = await fixture();
    final original = AudioTimeline.full(6000);
    final edited = original.remove(2000, 4000);
    final extracted = edited.extract(1000, 3000);
    for (final doc in [edited, extracted]) {
      final uri = await service.exportTimeline(
        file.path,
        doc.spans.map((s) => s.toExportRange()).toList(),
        '内部验证_${DateTime.now().microsecondsSinceEpoch}',
      );
      uris.add(uri);
      final item = (await service.queryRingtones()).singleWhere(
        (i) => i.uri == uri,
      );
      check(
        (item.duration - doc.durationMs).abs() < 160,
        '导出时长错误：${item.duration} vs ${doc.durationMs}',
      );
      final copy = File(await service.shareCopy(uri));
      copies.add(copy);
      final peaks = (await service.getWaveform(
        copy.path,
        'smoke-${doc.durationMs}',
      )).peaks;
      double average(double begin, double end) {
        final samples = peaks.sublist(
          (peaks.length * begin).round(),
          (peaks.length * end).round(),
        );
        return samples.reduce((a, b) => a + b) / samples.length;
      }

      final left = average(.1, .35), right = average(.65, .9);
      debugPrint(
        'RINGTONE_SMOKE amplitudes duration=${item.duration} left=$left right=$right ratio=${right / left}',
      );
      // Compare the known 0.2:0.5 amplitude ratio. Peak normalization may
      // be dominated by AAC transients, so an absolute 0.7 floor is invalid.
      check(
        left > .01 && right / left > 1.8 && right / left < 3.2,
        '保留片段的相对幅度不匹配：$left / $right',
      );
      debugPrint(
        'RINGTONE_SMOKE PASS export duration=${item.duration} spans=${doc.spans.length}',
      );
    }
    for (final duration in [6000, 100]) {
      final uri = await service.exportTimeline(
        file.path,
        AudioTimeline.full(
          6000,
        ).extract(0, duration).spans.map((s) => s.toExportRange()).toList(),
        'fade_smoke_${DateTime.now().microsecondsSinceEpoch}',
        fadeInMs: 200,
        fadeOutMs: 200,
      );
      uris.add(uri);
      final item = (await service.queryRingtones()).singleWhere(
        (i) => i.uri == uri,
      );
      check((item.duration - duration).abs() < 160, 'Fade changed duration');
      final copy = File(await service.shareCopy(uri));
      copies.add(copy);
      if (duration == 6000) {
        final peaks = (await service.getWaveform(
          copy.path,
          'fade-smoke',
        )).peaks;
        double average(double a, double b) {
          final values = peaks.sublist(
            (peaks.length * a).round(),
            (peaks.length * b).round(),
          );
          return values.reduce((a, b) => a + b) / values.length;
        }

        final head = average(.003, .012) / average(.08, .15);
        final tail = average(.988, .997) / average(.85, .92);
        check(head < .65 && tail < .65, 'Fade envelope missing: $head / $tail');
        debugPrint('RINGTONE_SMOKE PASS fade head=$head tail=$tail');
      }
      debugPrint('RINGTONE_SMOKE PASS faded export duration=${item.duration}');
    }
    final player = AudioPlayer();
    try {
      await player.setVolume(0);
      await player.setAudioSource(
        ConcatenatingAudioSource(
          children: edited.spans
              .map(
                (span) => ClippingAudioSource(
                  child: AudioSource.uri(Uri.file(file.path)),
                  start: Duration(milliseconds: span.startMs),
                  end: Duration(milliseconds: span.endMs),
                ),
              )
              .toList(),
        ),
      );
      unawaited(player.play());
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await player.seek(const Duration(milliseconds: 1100), index: 0);
      check(player.playing, '段内拖动中断了播放');
      await player.seek(const Duration(milliseconds: 500), index: 1);
      check(player.playing && player.currentIndex == 1, '跨拼接点拖动失败');
      debugPrint('RINGTONE_SMOKE PASS uninterrupted seek across joined clips');
      await player.pause();
    } finally {
      await player.dispose();
    }
    debugPrint('RINGTONE_SMOKE ALL PASS');
    runApp(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF87A437)),
        ),
        home: EditorPage(filePath: file.path, isVideo: false),
      ),
    );
  } catch (error, stack) {
    debugPrint('RINGTONE_SMOKE FAIL $error\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('验证失败：$error'))),
      ),
    );
  } finally {
    for (final uri in uris) {
      await service.deleteRingtone(uri);
    }
    for (final copy in copies) {
      if (await copy.exists()) await copy.delete();
    }
  }
}
