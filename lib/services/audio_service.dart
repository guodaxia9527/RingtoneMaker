import 'dart:io';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');

class RingtoneInfo {
  final String uri;
  final String name;
  final String path;
  final int size;
  final int duration;

  RingtoneInfo({
    required this.uri,
    required this.name,
    required this.path,
    required this.size,
    required this.duration,
  });

  factory RingtoneInfo.fromMap(Map<dynamic, dynamic> map) {
    return RingtoneInfo(
      uri: map['uri'] as String,
      name: map['name'] as String,
      path: map['path'] as String,
      size: map['size'] as int,
      duration: map['duration'] as int,
    );
  }
}

class AudioService {
  /// 从视频或音频文件中提取音频
  Future<String> extractAudio(String sourcePath) async {
    final outputDir = await getTemporaryDirectory();
    final outputPath =
        '${outputDir.path}/extracted_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    final result = await AudioDecoder.convertToWav(sourcePath, outputPath);

    if (result == null) {
      throw Exception('音频提取失败：文件格式不支持或已损坏');
    }

    return outputPath;
  }

  /// 创建铃声 - 返回 URI 字符串
  Future<String> createRingtone(
    String audioPath,
    Duration startTime,
    Duration endTime,
  ) async {
    // 先在临时目录创建剪辑文件
    final outputDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempFileName = 'ringtone_temp_$timestamp.m4a';
    final tempPath = '${outputDir.path}/$tempFileName';

    // 剪辑音频
    final result = await AudioDecoder.trimAudio(
      audioPath,
      tempPath,
      startTime,
      endTime,
    );

    if (result == null) {
      throw Exception('铃声创建失败');
    }

    // 通过原生方法保存到 MediaStore，返回 URI
    final fileName = '铃声_$timestamp.m4a';
    final uri = await _channel.invokeMethod<String>('createFile', {
      'sourcePath': tempPath,
      'fileName': fileName,
    });

    // 删除临时文件
    try {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}

    if (uri == null) {
      throw Exception('铃声保存失败');
    }

    return uri; // 返回 content:// URI
  }

  /// 从 MediaStore 查询所有铃声
  Future<List<RingtoneInfo>> queryRingtones() async {
    final result = await _channel.invokeMethod<List<dynamic>>('queryRingtones');
    if (result == null) return [];

    return result
        .map((item) => RingtoneInfo.fromMap(item as Map<dynamic, dynamic>))
        .toList();
  }

  /// 删除铃声 - 通过 URI
  Future<bool> deleteRingtone(String uri) async {
    final result = await _channel.invokeMethod<bool>('deleteFile', {
      'uri': uri,
    });
    return result ?? false;
  }

  /// 获取音频信息（时长、采样率等）
  Future<AudioInfo?> getAudioInfo(String audioPath) async {
    final info = await AudioDecoder.getAudioInfo(audioPath);
    return info;
  }

  /// 获取波形数据用于可视化
  Future<List<double>> getWaveform(
    String audioPath, {
    int samples = 100,
  }) async {
    final waveform = await AudioDecoder.getWaveform(
      audioPath,
      numberOfSamples: samples,
    );
    if (waveform == null) {
      return [];
    }
    return waveform;
  }
}
