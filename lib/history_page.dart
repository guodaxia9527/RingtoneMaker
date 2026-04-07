import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/audio_service.dart';
import '../services/ringtone_service.dart';

const _channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');

class HistoryPage extends StatefulWidget {
  final String? autoplayPath;

  const HistoryPage({super.key, this.autoplayPath});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RingtoneService _ringtoneService = RingtoneService();

  List<RingtoneFile> _ringtones = [];
  bool _isLoading = true;
  String? _currentlyPlayingPath;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRingtones();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadRingtones() async {
    setState(() => _isLoading = true);

    try {
      // 从 MediaStore 查询铃声
      final ringtonesInfo = await _audioService.queryRingtones();

      final ringtones = ringtonesInfo
          .map(
            (info) => RingtoneFile(
              uri: info.uri,
              path: info.path,
              name: info.name,
              size: info.size,
              duration: Duration(milliseconds: info.duration),
            ),
          )
          .toList();

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
    if (_currentlyPlayingPath == path) {
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
      setState(() {
        _currentlyPlayingPath = path;
      });
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

  Future<void> _renameFile(RingtoneFile ringtone) async {
    final controller = TextEditingController(
      text: ringtone.name.replaceAll('.m4a', ''),
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名铃声'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件名',
            suffixText: '.m4a',
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != ringtone.name.replaceAll('.m4a', '')) {
      try {
        final oldFile = File(ringtone.path);
        final directory = oldFile.parent.path;
        String finalName = newName;
        // 过滤非法字符
        finalName = finalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        if (!finalName.endsWith('.m4a')) {
          finalName = '$finalName.m4a';
        }

        final newPath = '$directory/$finalName';
        await oldFile.rename(newPath);

        // 如果正在播放这个文件，更新路径
        if (_currentlyPlayingPath == ringtone.path) {
          setState(() {
            _currentlyPlayingPath = newPath;
          });
        }

        _loadRingtones();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('重命名成功')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
        }
      }
    }
  }

  Future<void> _showRingtoneTypeDialog(RingtoneFile ringtone) async {
    final result = await showDialog<RingtoneType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择铃声类型'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RingtoneType.ringtone),
            child: Row(
              children: [
                Icon(Icons.phone, color: Colors.green),
                SizedBox(width: 16),
                Text('来电铃声'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RingtoneType.alarm),
            child: Row(
              children: [
                Icon(Icons.alarm, color: Colors.orange),
                SizedBox(width: 16),
                Text('闹钟铃声'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RingtoneType.notification),
            child: Row(
              children: [
                Icon(Icons.notifications, color: Colors.blue),
                SizedBox(width: 16),
                Text('通知铃声'),
              ],
            ),
          ),
        ],
      ),
    );

    if (result != null) {
      await _setAsRingtone(ringtone.path, result);
    }
  }

  Future<void> _setAsRingtone(String filePath, RingtoneType type) async {
    try {
      final hasPermission = await _ringtoneService.hasWriteSettingsPermission();

      if (!hasPermission) {
        await _ringtoneService.requestWriteSettingsPermission();

        bool permissionGranted = false;
        for (int i = 0; i < 30; i++) {
          await Future.delayed(Duration(milliseconds: 500));
          permissionGranted = await _ringtoneService
              .hasWriteSettingsPermission();
          if (permissionGranted) break;
        }

        if (!permissionGranted) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('需要授予修改系统设置的权限')));
          }
          return;
        }
      }

      final success = await _ringtoneService.setAsRingtone(filePath, type);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已设为${_ringtoneService.getRingtoneTypeName(type)}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置铃声失败')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置铃声失败: $e')));
      }
    }
  }

  Future<void> _deleteFile(RingtoneFile ringtone) async {
    if (_currentlyPlayingPath == ringtone.path) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlayingPath = null;
      });
    }

    try {
      final result = await _audioService.deleteRingtone(ringtone.uri);

      if (result) {
        _loadRingtones();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除成功')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除失败: 无法删除文件')));
        }
      }
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
                      final isCurrentFile =
                          _currentlyPlayingPath == ringtone.path;

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
                                      Row(
                                        children: [
                                          // 播放图标
                                          GestureDetector(
                                            onTap: () =>
                                                _togglePlay(ringtone.path),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
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
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // 文件名（点击播放，长按更名）
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _togglePlay(ringtone.path),
                                              onLongPress: () =>
                                                  _renameFile(ringtone),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            ringtone.name,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color:
                                                                  isCurrentFile
                                                                  ? Colors.green
                                                                  : null,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        // 设为铃声图标
                                                        GestureDetector(
                                                          onTap: () =>
                                                              _showRingtoneTypeDialog(
                                                                ringtone,
                                                              ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 8,
                                                                ),
                                                            child: Icon(
                                                              Icons
                                                                  .notifications_active,
                                                              color:
                                                                  Colors.orange,
                                                              size: 20,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
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
                                            ),
                                          ),
                                        ],
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
  final String uri; // content:// URI for MediaStore
  final String path; // 实际文件路径
  final String name;
  final int size;
  final Duration duration;

  RingtoneFile({
    required this.uri,
    required this.path,
    required this.name,
    required this.size,
    required this.duration,
  });
}
