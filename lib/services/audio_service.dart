import 'dart:io';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  /// 从视频或音频文件中提取音频
  /// audio_decoder 使用原生 API 解码并转换为 WAV
  Future<String> extractAudio(String sourcePath) async {
    final outputDir = await getTemporaryDirectory();
    final outputPath =
        '${outputDir.path}/extracted_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    // audio_decoder 支持从大多数音视频格式提取音频
    // 先转换为 WAV（通用格式），再后续处理
    final result = await AudioDecoder.convertToWav(sourcePath, outputPath);

    if (result == null) {
      throw Exception('音频提取失败：文件格式不支持或已损坏');
    }

    return outputPath;
  }

  /// 创建铃声 - 剪辑指定时间段
  /// 保存到公共 Download 目录，方便用户查找
  Future<String> createRingtone(
    String audioPath,
    Duration startTime,
    Duration endTime,
  ) async {
    // 使用公共 Download 目录
    final downloadDir = Directory('/storage/emulated/0/Download');

    // 确保 Download 目录存在
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '铃声_$timestamp.m4a';
    final outputPath = '${downloadDir.path}/$fileName';

    // 使用 trimAudio 剪辑指定范围，输出为 M4A
    final result = await AudioDecoder.trimAudio(
      audioPath,
      outputPath,
      startTime,
      endTime,
    );

    if (result == null) {
      throw Exception('铃声创建失败');
    }

    return outputPath;
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
