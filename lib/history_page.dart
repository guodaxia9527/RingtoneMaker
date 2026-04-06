import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/audio_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<RingtoneFile> _ringtones = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRingtones();
  }

  Future<void> _loadRingtones() async {
    setState(() => _isLoading = true);

    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        setState(() {
          _ringtones = [];
          _isLoading = false;
        });
        return;
      }

      final files = await downloadDir.list().toList();
      final m4aFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a') && f.path.contains('铃声_'))
          .toList();

      final ringtones = <RingtoneFile>[];

      for (final file in m4aFiles) {
        try {
          final stat = await file.stat();
          final info = await _audioService.getAudioInfo(file.path);

          ringtones.add(
            RingtoneFile(
              path: file.path,
              name: file.path.split('/').last,
              size: stat.size,
              duration: info?.duration ?? Duration.zero,
            ),
          );
        } catch (e) {
          // 忽略读取失败的文件
        }
      }

      ringtones.sort((a, b) => b.name.compareTo(a.name));

      setState(() {
        _ringtones = ringtones;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _ringtones = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlay(String path) async {
    final currentPath = _audioPlayer.sequence?.firstOrNull?.tag as String?;

    if (currentPath == path) {
      // 当前正在播放这个文件，切换暂停/播放
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play();
      }
    } else {
      // 切换到新文件
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(path);
      await _audioPlayer.play();
    }
  }

  Future<void> _seekTo(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> _openFile(String path) async {
    final result = await OpenFile.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开文件: ${result.message}')));
    }
  }

  Future<void> _shareFile(String path) async {
    await Share.shareXFiles([XFile(path)], text: '铃声');
  }

  Future<void> _deleteFile(RingtoneFile ringtone) async {
    final currentPath = _audioPlayer.sequence?.firstOrNull?.tag as String?;

    if (currentPath == ringtone.path) {
      await _audioPlayer.stop();
    }

    try {
      final file = File(ringtone.path);
      if (await file.exists()) {
        await file.delete();
      }
      _loadRingtones();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的铃声'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRingtones,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ringtones.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无铃声',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '导出的铃声会显示在这里',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRingtones,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _ringtones.length,
                itemBuilder: (context, index) {
                  final ringtone = _ringtones[index];

                  // 使用 StreamBuilder 实时监听播放器状态
                  return StreamBuilder<PlayerState>(
                    stream: _audioPlayer.playerStateStream,
                    builder: (context, stateSnapshot) {
                      final isPlaying = stateSnapshot.data?.playing ?? false;
                      final currentPath =
                          _audioPlayer.sequence?.firstOrNull?.tag as String?;
                      final isCurrentFile = currentPath == ringtone.path;

                      return StreamBuilder<Duration>(
                        stream: _audioPlayer.positionStream,
                        builder: (context, positionSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;

                          return StreamBuilder<Duration?>(
                            stream: _audioPlayer.durationStream,
                            builder: (context, durationSnapshot) {
                              final duration =
                                  durationSnapshot.data ?? ringtone.duration;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 文件名和播放按钮
                                      InkWell(
                                        onTap: () => _togglePlay(ringtone.path),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isCurrentFile && isPlaying
                                                    ? Icons.pause_circle
                                                    : Icons.play_circle_outline,
                                                color: isCurrentFile
                                                    ? Colors.green
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                size: 28,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      ringtone.name,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: isCurrentFile
                                                            ? Colors.green
                                                            : null,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.timer_outlined,
                                                          size: 14,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          _formatDuration(
                                                            ringtone.duration,
                                                          ),
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[600],
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Icon(
                                                          Icons
                                                              .storage_outlined,
                                                          size: 14,
                                                          color:
                                                              Colors.grey[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          _formatSize(
                                                            ringtone.size,
                                                          ),
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[600],
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // 当前播放文件的进度条（可拖动）
                                      if (isCurrentFile) ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Text(
                                              _formatDuration(position),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  trackHeight: 4,
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                        enabledThumbRadius: 6,
                                                      ),
                                                  overlayShape:
                                                      const RoundSliderOverlayShape(
                                                        overlayRadius: 12,
                                                      ),
                                                ),
                                                child: Slider(
                                                  value: position.inMilliseconds
                                                      .toDouble()
                                                      .clamp(
                                                        0,
                                                        duration.inMilliseconds
                                                            .toDouble(),
                                                      ),
                                                  min: 0,
                                                  max: duration.inMilliseconds
                                                      .toDouble(),
                                                  divisions:
                                                      duration.inMilliseconds >
                                                          0
                                                      ? (duration.inMilliseconds ~/
                                                                100)
                                                            .clamp(1, 100)
                                                      : 1,
                                                  activeColor: Colors.green,
                                                  inactiveColor:
                                                      Colors.grey[300],
                                                  onChanged: (value) {
                                                    _seekTo(
                                                      Duration(
                                                        milliseconds: value
                                                            .round(),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDuration(duration),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],

                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () =>
                                                _openFile(ringtone.path),
                                            icon: const Icon(
                                              Icons.open_in_new,
                                              size: 18,
                                            ),
                                            label: const Text('打开'),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _shareFile(ringtone.path),
                                            icon: const Icon(
                                              Icons.share,
                                              size: 18,
                                            ),
                                            label: const Text('分享'),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _deleteFile(ringtone),
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: Colors.red[400],
                                            ),
                                            label: Text(
                                              '删除',
                                              style: TextStyle(
                                                color: Colors.red[400],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

class RingtoneFile {
  final String path;
  final String name;
  final int size;
  final Duration duration;

  RingtoneFile({
    required this.path,
    required this.name,
    required this.size,
    required this.duration,
  });
}
