import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/audio_service.dart';
import '../services/ringtone_service.dart';
import 'history_page.dart';

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

        // 播放到达终点后停止
        if (_isPlaying && position >= _endTime) {
          _audioPlayer.pause();
          setState(() {
            _isPlaying = false;
            _position = _endTime;
          });
          return;
        }

        setState(() => _position = position);
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

  void _togglePlay() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      // 确保播放位置在选区内
      if (_position < _startTime || _position >= _endTime) {
        _audioPlayer.seek(_startTime);
      }
      _audioPlayer.play();
    }
  }

  void _onStartChanged(Duration newStart) {
    // 应用最小6秒限制
    var clampedStart = newStart;
    if (_endTime - clampedStart < _minRange) {
      clampedStart = _endTime - _minRange;
    }
    if (clampedStart < Duration.zero) {
      clampedStart = Duration.zero;
    }

    setState(() {
      _startTime = clampedStart;
      // 如果播放位置在新的起点之前，跳转到起点
      if (_position < _startTime) {
        _position = _startTime;
      }
    });

    // 跳转到起点位置
    if (!_isPlaying) {
      _audioPlayer.seek(_startTime);
    }
  }

  void _onEndChanged(Duration newEnd) {
    // 应用最小6秒限制
    var clampedEnd = newEnd;
    if (clampedEnd - _startTime < _minRange) {
      clampedEnd = _startTime + _minRange;
    }
    if (clampedEnd > _duration) {
      clampedEnd = _duration;
    }

    setState(() {
      _endTime = clampedEnd;
      // 如果播放位置在新的终点之后，跳转到"终点-6秒"
      if (_position > _endTime) {
        _position = _endTime - _minRange;
        if (_position < _startTime) {
          _position = _startTime;
        }
      }
    });

    // 跳转到"终点-6秒"位置
    if (!_isPlaying) {
      var seekPosition = _endTime - _minRange;
      if (seekPosition < _startTime) {
        seekPosition = _startTime;
      }
      _audioPlayer.seek(seekPosition);
    }
  }

  void _onPositionChanged(Duration newPosition) {
    // 限制播放位置在选区内
    var clampedPosition = newPosition;
    if (clampedPosition < _startTime) {
      clampedPosition = _startTime;
    } else if (clampedPosition > _endTime) {
      clampedPosition = _endTime;
    }

    setState(() => _position = clampedPosition);
    _audioPlayer.seek(clampedPosition);
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

  Future<void> _exportRingtone() async {
    if (_endTime <= _startTime) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请确保结束时间晚于起始时间')));
      return;
    }

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
        barrierDismissible: false,
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
              Text(
                '保存位置: /Download/RingtoneMaker/',
                style: TextStyle(fontSize: 13),
              ),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryPage(autoplayPath: outputPath),
                  ),
                );
              },
              icon: Icon(Icons.visibility),
              label: Text('查看'),
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
    final milliseconds = twoDigits(
      duration.inMilliseconds.remainder(1000) ~/ 10,
    );
    return '$minutes:$seconds.$milliseconds';
  }

  String _formatSimpleDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatRange(Duration start, Duration end) {
    final diff = end - start;
    return '${_formatSimpleDuration(start)} - ${_formatSimpleDuration(end)} (${_formatSimpleDuration(diff)})';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '总时长: ${_formatSimpleDuration(_duration)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
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
                        SizedBox(height: 40),
                        // 自定义音频轨道
                        CustomAudioTrack(
                          duration: _duration,
                          startTime: _startTime,
                          endTime: _endTime,
                          position: _position,
                          onStartChanged: _onStartChanged,
                          onEndChanged: _onEndChanged,
                          onPositionChanged: _onPositionChanged,
                        ),
                        SizedBox(height: 24),
                        // 时间标签
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '起点: ${_formatSimpleDuration(_startTime)}',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '终点: ${_formatSimpleDuration(_endTime)}',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    _formatDuration(_position),
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Spacer(),
                        // 播放按钮
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _isPlaying ? Colors.orange : Colors.green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                        Spacer(),
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

/// 完全自定义的音频轨道组件
/// 包含：灰色背景轨道、绿色选区高亮、起点/终点手柄、播放头
/// 每个手柄都是独立的 StatefulWidget，拖动时只更新本地状态，结束后再回调
class CustomAudioTrack extends StatelessWidget {
  final Duration duration;
  final Duration startTime;
  final Duration endTime;
  final Duration position;
  final ValueChanged<Duration> onStartChanged;
  final ValueChanged<Duration> onEndChanged;
  final ValueChanged<Duration> onPositionChanged;

  const CustomAudioTrack({
    super.key,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.position,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onPositionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;

        return Container(
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. 底部灰色轨道（整个音频时长）
              Positioned(
                left: 20,
                right: 20,
                top: 30,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 2. 绿色选区高亮（从起点到终点）
              _buildSelectionHighlight(trackWidth),

              // 3. 绿色起点手柄（左侧）- 独立 StatefulWidget
              _StartHandle(
                trackWidth: trackWidth,
                duration: duration,
                startTime: startTime,
                endTime: endTime,
                onChangeEnd: onStartChanged,
              ),

              // 4. 红色终点手柄（右侧）- 独立 StatefulWidget
              _EndHandle(
                trackWidth: trackWidth,
                duration: duration,
                startTime: startTime,
                endTime: endTime,
                onChangeEnd: onEndChanged,
              ),

              // 5. 蓝色播放头（可在选区内拖动）- 独立 StatefulWidget
              _PlayheadHandle(
                trackWidth: trackWidth,
                duration: duration,
                startTime: startTime,
                endTime: endTime,
                position: position,
                onChangeEnd: onPositionChanged,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建选区高亮区域
  Widget _buildSelectionHighlight(double trackWidth) {
    final usableWidth = trackWidth - 40;
    final startPx = _durationToPixel(startTime, usableWidth) + 20;
    final endPx = _durationToPixel(endTime, usableWidth) + 20;
    final width = endPx - startPx;

    return Positioned(
      left: startPx,
      top: 28,
      child: Container(
        width: width,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// 将Duration转换为像素位置
  static double durationToPixel(
    Duration d,
    Duration total,
    double usableWidth,
  ) {
    if (total.inMilliseconds <= 0) return 0;
    return (d.inMilliseconds / total.inMilliseconds) * usableWidth;
  }

  /// 将像素偏移转换为毫秒
  static double pixelToDurationMs(
    double pixel,
    Duration total,
    double usableWidth,
  ) {
    if (usableWidth <= 0) return 0;
    return (pixel / usableWidth) * total.inMilliseconds;
  }

  double _durationToPixel(Duration d, double usableWidth) {
    return durationToPixel(d, duration, usableWidth);
  }
}

/// 起点手柄 - 独立的 StatefulWidget
/// 拖动时只更新本地状态，拖动结束后才回调父组件
class _StartHandle extends StatefulWidget {
  final double trackWidth;
  final Duration duration;
  final Duration startTime;
  final Duration endTime;
  final ValueChanged<Duration> onChangeEnd;

  const _StartHandle({
    required this.trackWidth,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.onChangeEnd,
  });

  @override
  State<_StartHandle> createState() => _StartHandleState();
}

class _StartHandleState extends State<_StartHandle> {
  double _localPixel = 0;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _StartHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 非拖动状态下，同步外部位置
    if (!_isDragging && widget.startTime != oldWidget.startTime) {
      _syncFromDuration();
    }
  }

  void _syncFromDuration() {
    final usableWidth = widget.trackWidth - 40;
    _localPixel = CustomAudioTrack.durationToPixel(
      widget.startTime,
      widget.duration,
      usableWidth,
    );
  }

  void _onDragStart(DragStartDetails details) {
    _syncFromDuration();
    setState(() {
      _isDragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _localPixel += details.delta.dx;
      // 限制范围：0 到 (终点 - 6秒) 之间
      final usableWidth = widget.trackWidth - 40;
      final minPixel = 0.0;
      final maxDuration = widget.endTime - const Duration(seconds: 6);
      final maxPixel = CustomAudioTrack.durationToPixel(
        maxDuration,
        widget.duration,
        usableWidth,
      );
      _localPixel = _localPixel.clamp(minPixel, maxPixel);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final usableWidth = widget.trackWidth - 40;
    final newMs = CustomAudioTrack.pixelToDurationMs(
      _localPixel,
      widget.duration,
      usableWidth,
    );
    final newStart = Duration(
      milliseconds: newMs.round().clamp(0, widget.duration.inMilliseconds),
    );

    setState(() {
      _isDragging = false;
    });

    // 拖动结束后再回调父组件
    widget.onChangeEnd(newStart);
  }

  @override
  Widget build(BuildContext context) {
    final usableWidth = widget.trackWidth - 40;
    // 使用本地位置（拖动中）或计算位置（非拖动中）
    final displayPixel = _isDragging
        ? _localPixel
        : CustomAudioTrack.durationToPixel(
            widget.startTime,
            widget.duration,
            usableWidth,
          );
    final leftPosition = displayPixel + 20 - 20; // +20轨道偏移 -20手柄中心

    return Positioned(
      left: leftPosition,
      top: 0,
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Container(
          width: 40,
          height: 60,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 20, color: Colors.green),
            ],
          ),
        ),
      ),
    );
  }
}

/// 终点手柄 - 独立的 StatefulWidget
class _EndHandle extends StatefulWidget {
  final double trackWidth;
  final Duration duration;
  final Duration startTime;
  final Duration endTime;
  final ValueChanged<Duration> onChangeEnd;

  const _EndHandle({
    required this.trackWidth,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.onChangeEnd,
  });

  @override
  State<_EndHandle> createState() => _EndHandleState();
}

class _EndHandleState extends State<_EndHandle> {
  double _localPixel = 0;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _EndHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.endTime != oldWidget.endTime) {
      _syncFromDuration();
    }
  }

  void _syncFromDuration() {
    final usableWidth = widget.trackWidth - 40;
    _localPixel = CustomAudioTrack.durationToPixel(
      widget.endTime,
      widget.duration,
      usableWidth,
    );
  }

  void _onDragStart(DragStartDetails details) {
    _syncFromDuration();
    setState(() {
      _isDragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _localPixel += details.delta.dx;
      // 限制范围：(起点 + 6秒) 到 总时长 之间
      final usableWidth = widget.trackWidth - 40;
      final minDuration = widget.startTime + const Duration(seconds: 6);
      final minPixel = CustomAudioTrack.durationToPixel(
        minDuration,
        widget.duration,
        usableWidth,
      );
      final maxPixel = usableWidth.toDouble();
      _localPixel = _localPixel.clamp(minPixel, maxPixel);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final usableWidth = widget.trackWidth - 40;
    final newMs = CustomAudioTrack.pixelToDurationMs(
      _localPixel,
      widget.duration,
      usableWidth,
    );
    final newEnd = Duration(
      milliseconds: newMs.round().clamp(0, widget.duration.inMilliseconds),
    );

    setState(() {
      _isDragging = false;
    });

    widget.onChangeEnd(newEnd);
  }

  @override
  Widget build(BuildContext context) {
    final usableWidth = widget.trackWidth - 40;
    final displayPixel = _isDragging
        ? _localPixel
        : CustomAudioTrack.durationToPixel(
            widget.endTime,
            widget.duration,
            usableWidth,
          );
    final leftPosition = displayPixel + 20 - 20;

    return Positioned(
      left: leftPosition,
      top: 0,
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Container(
          width: 40,
          height: 60,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 20, color: Colors.red),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放头手柄 - 独立的 StatefulWidget
class _PlayheadHandle extends StatefulWidget {
  final double trackWidth;
  final Duration duration;
  final Duration startTime;
  final Duration endTime;
  final Duration position;
  final ValueChanged<Duration> onChangeEnd;

  const _PlayheadHandle({
    required this.trackWidth,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.position,
    required this.onChangeEnd,
  });

  @override
  State<_PlayheadHandle> createState() => _PlayheadHandleState();
}

class _PlayheadHandleState extends State<_PlayheadHandle> {
  double _localPixel = 0;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _PlayheadHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.position != oldWidget.position) {
      _syncFromDuration();
    }
  }

  void _syncFromDuration() {
    final usableWidth = widget.trackWidth - 40;
    // 限制在选区内
    var clampedPosition = widget.position;
    if (clampedPosition < widget.startTime) clampedPosition = widget.startTime;
    if (clampedPosition > widget.endTime) clampedPosition = widget.endTime;

    _localPixel = CustomAudioTrack.durationToPixel(
      clampedPosition,
      widget.duration,
      usableWidth,
    );
  }

  void _onDragStart(DragStartDetails details) {
    _syncFromDuration();
    setState(() {
      _isDragging = true;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _localPixel += details.delta.dx;
      // 限制在选区内
      final usableWidth = widget.trackWidth - 40;
      final minPixel = CustomAudioTrack.durationToPixel(
        widget.startTime,
        widget.duration,
        usableWidth,
      );
      final maxPixel = CustomAudioTrack.durationToPixel(
        widget.endTime,
        widget.duration,
        usableWidth,
      );
      _localPixel = _localPixel.clamp(minPixel, maxPixel);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final usableWidth = widget.trackWidth - 40;
    final newMs = CustomAudioTrack.pixelToDurationMs(
      _localPixel,
      widget.duration,
      usableWidth,
    );
    // 限制在选区内
    final minMs = widget.startTime.inMilliseconds;
    final maxMs = widget.endTime.inMilliseconds;
    final clampedMs = newMs.round().clamp(minMs, maxMs);
    final newPosition = Duration(milliseconds: clampedMs);

    setState(() {
      _isDragging = false;
    });

    widget.onChangeEnd(newPosition);
  }

  @override
  Widget build(BuildContext context) {
    final usableWidth = widget.trackWidth - 40;
    // 限制显示位置在选区内
    var clampedPosition = widget.position;
    if (clampedPosition < widget.startTime) clampedPosition = widget.startTime;
    if (clampedPosition > widget.endTime) clampedPosition = widget.endTime;

    final displayPixel = _isDragging
        ? _localPixel
        : CustomAudioTrack.durationToPixel(
            clampedPosition,
            widget.duration,
            usableWidth,
          );
    final leftPosition = displayPixel + 20 - 15; // +20轨道偏移 -15手柄中心

    return Positioned(
      left: leftPosition,
      top: 0,
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Container(
          width: 30,
          height: 80,
          color: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 64, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
  }
}
