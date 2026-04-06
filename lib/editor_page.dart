import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../services/audio_service.dart';
import '../services/ringtone_service.dart';

class EditorPage extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const EditorPage({super.key, required this.filePath, required this.isVideo});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioService _audioService = AudioService();
  final RingtoneService _ringtoneService = RingtoneService();

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _startTime = Duration.zero;
  Duration _endTime = Duration.zero;
  bool _isPlaying = false;
  bool _isExporting = false;
  bool _isLoading = true;
  String? _audioPath;
  String? _errorMessage;

  static const Duration _minRange = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String sourcePath = widget.filePath;

      if (widget.isVideo) {
        _audioPath = await _audioService.extractAudio(widget.filePath);
        sourcePath = _audioPath!;
      }

      await _audioPlayer.setFilePath(sourcePath);

      _audioPlayer.durationStream.listen((duration) {
        if (duration != null && mounted) {
          setState(() {
            _duration = duration;
            _endTime = duration;
            _startTime = Duration.zero;
            _isLoading = false;
          });
        }
      });

      _audioPlayer.positionStream.listen((position) {
        if (!mounted) return;
        setState(() => _position = position);

        if (_isPlaying && position >= _endTime) {
          _audioPlayer.seek(_startTime);
        }
      });

      _audioPlayer.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state.playing);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onRangeChanged(RangeValues values) {
    final newStart = Duration(milliseconds: values.start.round());
    var newEnd = Duration(milliseconds: values.end.round());

    // 确保最小范围
    if (newEnd - newStart < _minRange) {
      newEnd = newStart + _minRange;
    }

    // 确保不超过总时长
    if (newEnd > _duration) {
      newEnd = _duration;
    }

    if (newStart != _startTime || newEnd != _endTime) {
      // 如果播放点超出新范围，吸附到边界
      var adjustedPosition = _position;
      if (adjustedPosition < newStart) {
        adjustedPosition = newStart;
      } else if (adjustedPosition > newEnd) {
        adjustedPosition = newEnd;
      }

      setState(() {
        _startTime = newStart;
        _endTime = newEnd;
      });

      if (adjustedPosition != _position && !_isPlaying) {
        _audioPlayer.seek(adjustedPosition);
      }
    }
  }

  void _onPlayheadChanged(double value) {
    final newPosition = Duration(milliseconds: value.round());

    // 限制在选区范围内
    var clampedPosition = newPosition;
    if (clampedPosition < _startTime) {
      clampedPosition = _startTime;
    } else if (clampedPosition > _endTime) {
      clampedPosition = _endTime;
    }

    setState(() {
      _position = clampedPosition;
    });
    _audioPlayer.seek(clampedPosition);
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_position < _startTime || _position >= _endTime) {
        await _audioPlayer.seek(_startTime);
      }
      await _audioPlayer.play();
    }
  }

  Future<void> _showRingtoneTypeDialog(String filePath) async {
    final result = await showDialog<RingtoneType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('选择铃声类型'),
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
      await _setAsRingtone(filePath, result);
    }
  }

  Future<void> _setAsRingtone(String filePath, RingtoneType type) async {
    try {
      final hasPermission = await _ringtoneService.hasWriteSettingsPermission();

      if (!hasPermission) {
        // 请求权限
        await _ringtoneService.requestWriteSettingsPermission();

        // 等待用户授权后再次检查
        // 使用循环检查权限状态
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
            ).showSnackBar(SnackBar(content: Text('需要授予修改系统设置的权限才能设为铃声')));
          }
          return;
        }
      }

      final success = await _ringtoneService.setAsRingtone(filePath, type);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已成功设为${_ringtoneService.getRingtoneTypeName(type)}',
              ),
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

  Future<void> _exportRingtone() async {
    if (_endTime <= _startTime) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请确保结束时间晚于起始时间')));
      return;
    }

    // 先暂停播放
    if (_isPlaying) {
      await _audioPlayer.pause();
    }

    setState(() => _isExporting = true);

    try {
      final outputPath = await _audioService.createRingtone(
        widget.isVideo ? (_audioPath ?? widget.filePath) : widget.filePath,
        _startTime,
        _endTime,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('导出成功'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('铃声已保存到下载文件夹'),
              SizedBox(height: 8),
              Text(
                '文件名: ${outputPath.split('/').last}',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                OpenFile.open(outputPath);
              },
              icon: Icon(Icons.open_in_new),
              label: Text('打开'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Share.shareXFiles([XFile(outputPath)], text: '铃声');
              },
              icon: Icon(Icons.share),
              label: Text('分享'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showRingtoneTypeDialog(outputPath);
              },
              icon: Icon(Icons.notifications_active),
              label: Text('设为铃声'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatRange(Duration start, Duration end) {
    final diff = end - start;
    return '${_formatDuration(start)} - ${_formatDuration(end)} (${_formatDuration(diff)})';
  }

  double _durationToMillis(Duration d) {
    return d.inMilliseconds.toDouble();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;
    final maxDuration = _durationToMillis(_duration);

    return Scaffold(
      appBar: AppBar(
        title: const Text('剪辑铃声'),
        actions: [
          if (_isExporting)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _isLoading || _errorMessage != null
                  ? null
                  : _exportRingtone,
              icon: const Icon(Icons.save_alt),
              tooltip: '导出',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  widget.isVideo ? Icons.videocam : Icons.audio_file,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在加载音频...'),
                      ],
                    ),
                  )
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '加载失败',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('返回'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          _formatDuration(_duration),
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        SizedBox(height: 8),
                        Text(
                          '当前播放: ${_formatDuration(_position)}',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '选区: ${_formatRange(_startTime, _endTime)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 32),
                        IconButton.filled(
                          onPressed: _togglePlay,
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          iconSize: 48,
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.all(16),
                          ),
                        ),
                        const Spacer(),
                        // 播放进度条（独立一行）
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '播放位置',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                                Text(
                                  _formatDuration(_position),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                                overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                                activeTrackColor: Colors.green,
                                inactiveTrackColor: Colors.grey[300],
                                thumbColor: Colors.green,
                              ),
                              child: Slider(
                                value: _durationToMillis(_position).clamp(
                                  _durationToMillis(_startTime),
                                  _durationToMillis(_endTime),
                                ),
                                min: _durationToMillis(_startTime),
                                max: _durationToMillis(_endTime),
                                divisions: _duration.inMilliseconds > 0
                                    ? ((_endTime - _startTime).inMilliseconds ~/
                                              100)
                                          .clamp(1, 100)
                                    : 1,
                                onChanged: _onPlayheadChanged,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        // 选区范围滑块（独立一行）
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '铃声选区',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey),
                                ),
                                Text(
                                  '${_formatDuration(_startTime)} - ${_formatDuration(_endTime)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            RangeSlider(
                              values: RangeValues(
                                _durationToMillis(_startTime),
                                _durationToMillis(_endTime),
                              ),
                              min: 0,
                              max: maxDuration.clamp(1, double.infinity),
                              divisions: _duration.inMilliseconds > 0
                                  ? (_duration.inMilliseconds ~/ 100).clamp(
                                      1,
                                      1000,
                                    )
                                  : 1,
                              activeColor: Colors.orange,
                              inactiveColor: Colors.grey[300],
                              onChanged: _onRangeChanged,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _isLoading || _errorMessage != null || _isExporting
                ? null
                : _exportRingtone,
            icon: _isExporting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.save_alt),
            label: Text(_isExporting ? '导出中...' : '导出铃声'),
            style: FilledButton.styleFrom(minimumSize: Size.fromHeight(56)),
          ),
        ),
      ),
    );
  }
}
