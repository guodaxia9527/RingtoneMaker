import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ringtone_maker/app_theme.dart';
import 'package:ringtone_maker/editor_page.dart';
import 'package:ringtone_maker/services/audio_service.dart';
import 'device_smoke.dart' as smoke;

// Independent release-mode device harness; never included by lib/main.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('正在验证波形…'))),
    ),
  );
  const path = String.fromEnvironment('REFERENCE_URI');
  final service = AudioService();
  final player = AudioPlayer();
  try {
    if (path.isEmpty) {
      throw StateError('Set REFERENCE_URI for this device harness');
    }
    final watch = Stopwatch()..start();
    int? first;
    final ready = player.setAudioSource(AudioSource.uri(Uri.parse(path))).then((
      duration,
    ) {
      debugPrint(
        'WAVE_BENCH playerMs=${watch.elapsedMilliseconds} duration=${duration?.inMilliseconds}',
      );
    });
    final wave = await service.getWaveform(
      path,
      'bench-cold',
      onProgress: (data) {
        first ??= watch.elapsedMilliseconds;
        debugPrint(
          'WAVE_BENCH progressMs=${watch.elapsedMilliseconds} available=${data.available}/${data.rms.length} gain=${data.gain}',
        );
      },
    );
    debugPrint(
      'WAVE_BENCH coldMs=${watch.elapsedMilliseconds} firstMs=$first cache=${wave.cacheHit} bins=${wave.rms.length} gain=${wave.gain}',
    );
    await ready;
    smoke.check(
      wave.durationMs > 4000,
      'Use a reference longer than four seconds',
    );
    final second = Stopwatch()..start();
    final cached = await service.getWaveform(path, 'bench-warm');
    smoke.check(
      cached.cacheHit && (cached.gain - wave.gain).abs() < 1e-8,
      'Cache/gain mismatch',
    );
    smoke.check(cached.rms.length == wave.rms.length, 'Cache length mismatch');
    debugPrint(
      'WAVE_BENCH warmMs=${second.elapsedMilliseconds} cache=${cached.cacheHit}',
    );
    final dir = (await getExternalStorageDirectory())!;
    await File('${dir.path}/wave-benchmark.json').writeAsString(
      jsonEncode({
        'durationMs': wave.durationMs,
        'gain': wave.gain,
        'rms': wave.rms,
        'peaks': wave.peaks,
      }),
    );
    // Exercise content-URI export and real decoding of the joined result.
    final exported = await service.exportTimeline(path, [
      {'startUs': 1000000, 'endUs': 2000000},
      {'startUs': 3000000, 'endUs': 4000000},
    ], 'wave_uri_verification');
    try {
      final p = AudioPlayer();
      try {
        final d = await p.setAudioSource(AudioSource.uri(Uri.parse(exported)));
        smoke.check(
          d != null && (d.inMilliseconds - 2000).abs() < 180,
          'URI export duration',
        );
      } finally {
        await p.dispose();
      }
    } finally {
      await service.deleteRingtone(exported);
    }
    debugPrint('WAVE_BENCH PASS URI export and cache');
    await smoke.main();
    runApp(
      MaterialApp(
        theme: buildAppTheme(),
        home: const EditorPage(
          key: ValueKey('reference-waveform'),
          filePath: path,
          isVideo: false,
          displayName: String.fromEnvironment(
            'REFERENCE_NAME',
            defaultValue: '波形验证',
          ),
        ),
      ),
    );
  } catch (e, stack) {
    debugPrint('WAVE_BENCH FAIL $e\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: Text('$e'))),
      ),
    );
  } finally {
    await player.dispose();
  }
}
