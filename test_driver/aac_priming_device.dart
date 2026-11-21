import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ringtone_maker/services/audio_service.dart';

// Device regression for AAC files whose first packet has a negative PTS.
// See fixtures/README.md. This entry point is never used by the shipped app.
void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('音频回归检查中'))),
    ),
  );
  final service = AudioService();
  final folder = (await getExternalStorageDirectory())!;
  final aac = '${folder.path}/aac_priming_regression.m4a';
  final temporary = <File>[];
  try {
    final wave = await service.getWaveform(aac, 'priming-cold');
    require(!wave.cacheHit, 'Fixture must start without a cached waveform');
    require((wave.durationMs - 3000).abs() < 100, 'AAC duration');
    require(wave.rms.any((v) => v > .03), 'AAC decoded no audible samples');
    require(wave.available == wave.rms.length, 'AAC analysis incomplete');
    final cached = await service.getWaveform(aac, 'priming-warm');
    require(
      cached.cacheHit && cached.rms.length == wave.rms.length,
      'Cache not reused',
    );
    for (var i = 0; i < wave.rms.length; i++) {
      require(
        (wave.rms[i] - cached.rms[i]).abs() < 1e-6,
        'Cached envelope changed',
      );
    }
    debugPrint('AAC_REGRESSION PASS negative-PTS waveform and cache');

    for (final startUs in [0, 1000000]) {
      final endUs = startUs + 1500000;
      final preview = await service.preview(aac, [
        {'startUs': startUs, 'endUs': endUs},
      ]);
      final player = AudioPlayer();
      try {
        final duration = await player.setFilePath(preview);
        require(
          duration != null && (duration.inMilliseconds - 1500).abs() < 100,
          'Preview duration',
        );
        final exported = await service.getWaveform(
          preview,
          'priming-preview-$startUs',
        );
        require(exported.rms.any((v) => v > .03), 'Preview is silent');
        debugPrint('AAC_REGRESSION PASS preview/export starting at $startUs');
      } finally {
        await player.dispose();
        await service.releasePreview(preview);
      }
    }

    // Genuine digital silence must remain valid; distinguish it from no PCM output.
    for (final samples in [44100, 0]) {
      final data = ByteData(44 + samples * 2);
      void ascii(int offset, String text) {
        for (var i = 0; i < text.length; i++)
          data.setUint8(offset + i, text.codeUnitAt(i));
      }

      ascii(0, 'RIFF');
      data.setUint32(4, data.lengthInBytes - 8, Endian.little);
      ascii(8, 'WAVEfmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, 44100, Endian.little);
      data.setUint32(28, 88200, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      ascii(36, 'data');
      data.setUint32(40, samples * 2, Endian.little);
      final file = File(
        '${(await getTemporaryDirectory()).path}/priming-silence-$samples.wav',
      );
      temporary.add(file);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (samples > 0) {
        final silent = await service.getWaveform(file.path, 'valid-silence');
        require(
          silent.rms.isNotEmpty && silent.rms.every((v) => v == 0),
          'Valid silence rejected',
        );
        debugPrint('AAC_REGRESSION PASS valid silent PCM');
      } else {
        var failed = false;
        try {
          await service.getWaveform(file.path, 'empty-track');
        } catch (_) {
          failed = true;
        }
        require(failed, 'Empty audio incorrectly treated as a silent waveform');
        debugPrint('AAC_REGRESSION PASS empty audio rejected');
      }
    }
    debugPrint('AAC_REGRESSION PASS ALL');
  } catch (error, stack) {
    debugPrint('AAC_REGRESSION FAIL $error\n$stack');
  } finally {
    for (final file in temporary) {
      if (await file.exists()) await file.delete();
    }
  }
}
