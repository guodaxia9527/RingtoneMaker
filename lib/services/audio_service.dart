import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../waveform_data.dart';
export '../waveform_data.dart';

const _channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');

class RingtoneInfo {
  final String uri;
  final String name;
  final int size;
  final int duration;
  final int createdAt;
  const RingtoneInfo({
    required this.uri,
    required this.name,
    required this.size,
    required this.duration,
    this.createdAt = 0,
  });
  factory RingtoneInfo.fromMap(Map<dynamic, dynamic> map) => RingtoneInfo(
    uri: map['uri'] as String,
    name: map['name'] as String,
    size: (map['size'] as num).toInt(),
    duration: (map['duration'] as num).toInt(),
    createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class AudioService {
  static final _progress = <String, void Function(Map<dynamic, dynamic>)>{};
  static bool _listening = false;

  Future<Map<dynamic, dynamic>?> pickSource() =>
      _channel.invokeMapMethod<dynamic, dynamic>('pickSource');

  Future<bool> consumeSelectionHint() async =>
      await _channel.invokeMethod<bool>('consumeSelectionHint') ?? false;

  Future<String> preview(
    String path,
    List<Map<String, int>> ranges, {
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) async => (await _channel.invokeMethod<String>('preview', {
    'path': path,
    'ranges': ranges,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
  }))!;

  Future<void> releasePreview(String path) =>
      _channel.invokeMethod('releasePreview', {'path': path});

  Future<WaveformData> getWaveform(
    String path,
    String requestId, {
    void Function(WaveformData)? onProgress,
  }) async {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'waveformProgress' && call.arguments is Map) {
          final map = call.arguments as Map;
          _progress[map['requestId']]?.call(map);
        }
      });
    }
    Float64List? partialPeaks, partialRms;
    List<double> read(dynamic value) => value is Float64List
        ? value
        : (value as List).map((v) => (v as num).toDouble()).toList();
    WaveformData parse(Map map, List<double> peaks, List<double> rms) =>
        WaveformData(
          peaks,
          rms,
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
          available: (map['available'] as num?)?.toInt() ?? rms.length,
          gain: (map['gain'] as num?)?.toDouble() ?? 1,
          cacheHit: map['cacheHit'] == true,
          elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
        );
    if (onProgress != null) {
      _progress[requestId] = (map) {
        final count = (map['count'] as num).toInt();
        partialPeaks ??= Float64List(count);
        partialRms ??= Float64List(count);
        final offset = (map['offset'] as num).toInt();
        final peaks = read(map['peaks']), rms = read(map['rms']);
        partialPeaks!.setRange(offset, offset + peaks.length, peaks);
        partialRms!.setRange(offset, offset + rms.length, rms);
        onProgress(
          parse(
            map,
            Float64List.fromList(partialPeaks!),
            Float64List.fromList(partialRms!),
          ),
        );
      };
    }
    try {
      final values = await _channel.invokeMethod<dynamic>('waveform', {
        'path': path,
        'requestId': requestId,
      });
      if (values is Map) {
        return parse(values, read(values['peaks']), read(values['rms']));
      }
      final legacy = read(values);
      return WaveformData(legacy, legacy);
    } finally {
      _progress.remove(requestId);
    }
  }

  Future<void> cancelAnalysis(String requestId) {
    _progress.remove(requestId);
    return _channel.invokeMethod('cancelAnalysis', {'requestId': requestId});
  }

  Future<String> createRingtone(
    String path,
    Duration start,
    Duration end,
    String name,
  ) async {
    return (await _channel.invokeMethod<String>('export', {
      'path': path,
      'startUs': start.inMicroseconds,
      'endUs': end.inMicroseconds,
      'fileName': name,
    }))!;
  }

  Future<String> exportTimeline(
    String path,
    List<Map<String, int>> ranges,
    String name, {
    int fadeInMs = 0,
    int fadeOutMs = 0,
  }) async {
    return (await _channel.invokeMethod<String>('export', {
      'path': path,
      'ranges': ranges,
      'fadeInMs': fadeInMs,
      'fadeOutMs': fadeOutMs,
      'fileName': name,
    }))!;
  }

  Future<List<RingtoneInfo>> queryRingtones() async {
    final result = await _channel.invokeMethod<List<dynamic>>('queryRingtones');
    return (result ?? []).map((v) => RingtoneInfo.fromMap(v as Map)).toList();
  }

  Future<bool> deleteRingtone(String uri) async =>
      await _channel.invokeMethod<bool>('deleteFile', {'uri': uri}) ?? false;
  Future<void> renameRingtone(String uri, String name) =>
      _channel.invokeMethod('renameFile', {'uri': uri, 'fileName': name});
  Future<String> shareCopy(String uri) async =>
      (await _channel.invokeMethod<String>('shareCopy', {'uri': uri}))!;
}
