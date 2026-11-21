import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_timeline.dart';
import 'edit_selection.dart';
import 'export_options.dart';
import 'history_page.dart';
import 'services/audio_service.dart';
import 'widgets/recorder_waveforms.dart';
import 'widgets/tail_filename.dart';
import 'widgets/recorder_action_icon.dart';
import 'widgets/saved_ringtone_sheet.dart';
import 'widgets/boundary_dialog.dart';
import 'widgets/save_ringtone_dialog.dart';

class EditorPage extends StatefulWidget {
  final String filePath;
  final String? displayName;
  final bool isVideo;
  final AudioPlayer? player;
  const EditorPage({
    super.key,
    required this.filePath,
    required this.isVideo,
    this.player,
    this.displayName,
  });
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditSnapshot {
  final AudioTimeline timeline;
  final EditSelection selection;
  final int position;
  const _EditSnapshot(this.timeline, this.selection, this.position);
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  late final _player = widget.player ?? AudioPlayer();
  final _service = AudioService();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _history = <_EditSnapshot>[];
  final _redoHistory = <_EditSnapshot>[];
  late final _requestId = DateTime.now().microsecondsSinceEpoch.toString();
  AudioTimeline? _timeline, _savedTimeline;
  int _fadeInMs = 0, _fadeOutMs = 0, _savedFadeInMs = 0, _savedFadeOutMs = 0;
  String? _exportName;
  bool _allowPop = false, _leaveDialogOpen = false, _overviewDragging = false;
  EditSelection? _selection;
  WaveformData? _waveform;
  String? _error, _waveError;
  int _position = 0, _windowMs = 6000;
  int? _dragOrigin, _playOrigin, _pendingSeek, _overviewReference;
  bool _wantPlaying = false, _interacting = false, _transition = false;
  bool _loopSelection = false, _endingPreview = false, _loopRestarting = false;
  bool _hintRequested = false;
  bool _positionMenuOpen = false;
  bool _waveLoading = true, _mediaBusy = false, _exporting = false;
  Future<void>? _seekTask, _boundaryPauseTask;
  int _interactionGeneration = 0;
  int? _activeBoundary;
  bool get _enabled =>
      _timeline != null && !_mediaBusy && !_exporting && !_transition;
  bool get _canMarkPosition =>
      _enabled && !_wantPlaying && !_player.playing && !_interacting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      _player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 16),
            maxPeriod: const Duration(milliseconds: 16),
          )
          .listen(_onPosition),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((state) {
        if (!mounted || _mediaBusy || _transition || _loopRestarting) return;
        if (state.processingState == ProcessingState.completed &&
            !_interacting &&
            _seekTask == null) {
          _stopAtEnd();
        } else if (!state.playing &&
            _wantPlaying &&
            !_player.playing &&
            !_interacting &&
            _seekTask == null) {
          setState(() {
            _wantPlaying = false;
            _playOrigin = null;
          });
        }
      }),
    );
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (mounted) {
            setState(() {
              _wantPlaying = false;
              _playOrigin = null;
            });
            _message('播放失败：$error');
          }
        },
      ),
    );
    unawaited(_load());
  }

  String get _fileName =>
      widget.displayName ??
      widget.filePath.replaceAll('\\', '/').split('/').last;
  Uri get _sourceUri => widget.filePath.startsWith('content://')
      ? Uri.parse(widget.filePath)
      : Uri.file(widget.filePath);

  Future<Duration?> _loadOriginal({Duration? initialPosition}) =>
      widget.filePath.startsWith('content://')
      ? _player.setAudioSource(
          AudioSource.uri(_sourceUri),
          initialPosition: initialPosition,
        )
      : _player.setFilePath(widget.filePath, initialPosition: initialPosition);

  Future<void> _loadWaveform() async {
    try {
      final waveform = await _service.getWaveform(
        widget.filePath,
        _requestId,
        onProgress: (data) {
          if (mounted) setState(() => _waveform = data);
        },
      );
      if (mounted) {
        setState(() {
          _waveform = waveform;
          _waveLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _waveError = '波形暂不可用，仍可拖动时间轴剪辑';
          _waveLoading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    // Player preparation and analysis use independent file descriptors.
    unawaited(_loadWaveform());
    try {
      final duration = await _loadOriginal();
      if (!mounted) return;
      if (duration == null || duration.inMilliseconds <= 0) {
        throw Exception('文件没有可播放的音轨');
      }
      setState(() {
        _timeline = AudioTimeline.full(duration.inMilliseconds);
        _savedTimeline = _timeline;
        _selection = EditSelection.full(duration.inMilliseconds);
      });
    } catch (e) {
      if (!mounted) return;
      unawaited(_service.cancelAnalysis(_requestId).catchError((Object _) {}));
      setState(() => _error = '无法读取音轨，请尝试其他文件。\n$e');
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _onPosition(Duration value) {
    if (!mounted ||
        _timeline == null ||
        _positionMenuOpen ||
        _interacting ||
        _seekTask != null ||
        _mediaBusy ||
        _transition ||
        _loopRestarting) {
      return;
    }
    final position = _timeline!.positionOf(
      _player.currentIndex ?? 0,
      value.inMilliseconds,
    );
    if (_wantPlaying && position >= _selection!.endMs) {
      _stopAtEnd();
    } else {
      setState(() => _position = position);
    }
  }

  void _stopAtEnd() {
    if (!mounted || !_wantPlaying || _selection == null) return;
    if (_loopSelection && !_endingPreview) {
      if (!_loopRestarting) unawaited(_restartLoop());
      return;
    }
    setState(() {
      _position = _selection!.endMs;
      _wantPlaying = false;
      _playOrigin = null;
      _endingPreview = false;
    });
    unawaited(_player.pause().catchError((Object e) => _message('暂停失败：$e')));
  }

  Future<void> _restartLoop() async {
    // A loop seek does not change whether the selection can be edited.
    // Keep its event guard separate from explicit play/pause transitions.
    _loopRestarting = true;
    final interaction = _interactionGeneration;
    try {
      _seek(_selection!.startMs);
      await _seekTask;
      // An edit, pause or waveform gesture takes ownership of playback while
      // the native seek is pending. Never resume over that newer action.
      if (!mounted ||
          !_wantPlaying ||
          _mediaBusy ||
          _exporting ||
          _transition ||
          _interacting ||
          interaction != _interactionGeneration) {
        return;
      }
      unawaited(
        _player.play().catchError((Object error) {
          if (mounted) {
            setState(() {
              _wantPlaying = false;
              _playOrigin = null;
            });
          }
          _message('试听失败：$error');
        }),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _wantPlaying = false;
          _playOrigin = null;
        });
      }
      _message('循环试听失败：$error');
    } finally {
      _loopRestarting = false;
    }
  }

  Future<void> _previewEnding() async {
    if (!_enabled) return;
    _endingPreview = true;
    _seek(
      math.max(_selection!.startMs, _selection!.endMs - 2000),
      clearReference: true,
    );
    await _seekTask;
    if (mounted && !_wantPlaying) await _togglePlay(ending: true);
  }

  Future<void> _adjustBoundary(bool start) async {
    if (!_enabled) return;
    setState(() {
      _wantPlaying = false;
      _playOrigin = null;
    });
    try {
      await _player.pause();
    } catch (e) {
      _message('暂停失败：$e');
      return;
    }
    if (!mounted) return;
    final value = await showDialog<int>(
      context: context,
      builder: (_) => BoundaryDialog(
        start: start,
        selection: _selection!,
        positionMs: _position,
      ),
    );
    if (mounted && value != null) _changeBoundary(value, start);
  }

  Future<void> _selectionHint() async {
    if (_hintRequested) return;
    _hintRequested = true;
    try {
      if (await _service.consumeSelectionHint() && mounted) {
        _message('保留：只留下蓝色选区；移除：删掉蓝色选区。');
      }
    } catch (_) {
      /* The hint must never prevent selection. */
    }
  }

  Future<void> _showPositionMenu(Offset globalPosition) async {
    if (!_enabled || _interacting || _positionMenuOpen) return;
    // Freeze the visible head as soon as the long press is recognized,
    // including while waiting for the native player to finish pausing.
    final position = _position;
    final selection = _selection!;
    _positionMenuOpen = true;
    bool? start;
    try {
      if (_wantPlaying || _player.playing) {
        setState(() {
          _wantPlaying = false;
          _playOrigin = null;
          _endingPreview = false;
          _transition = true;
        });
        try {
          await _player.pause();
        } catch (error) {
          _message('暂停失败：$error');
          return;
        } finally {
          if (mounted) setState(() => _transition = false);
        }
      }
      if (!mounted || !_canMarkPosition) return;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final anchor = overlay.globalToLocal(globalPosition);
      start = await showMenu<bool>(
        context: context,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        position: RelativeRect.fromRect(
          Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem<bool>(
            enabled: false,
            height: 36,
            child: Text(
              '当前播放位置 ${displayTime(position, fraction: true)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF74777A)),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<bool>(
            key: const ValueKey('mark-position-start'),
            value: true,
            enabled:
                position != selection.startMs &&
                position <= selection.endMs - selection.minimumMs,
            child: const Text('设置起点'),
          ),
          PopupMenuItem<bool>(
            key: const ValueKey('mark-position-end'),
            value: false,
            enabled:
                position != selection.endMs &&
                position >= selection.startMs + selection.minimumMs,
            child: const Text('设置终点'),
          ),
        ],
      );
    } finally {
      _positionMenuOpen = false;
    }
    if (!mounted || start == null || !_canMarkPosition) return;
    final current = _selection!;
    final next = start
        ? current.withStart(position)
        : current.withEnd(position);
    // Do not silently clamp a marker away from the playhead.
    if ((start ? next.startMs : next.endMs) == position) {
      _changeBoundary(position, start);
    }
  }

  void _toggleFromWaveform() {
    if (!_interacting && !_positionMenuOpen) unawaited(_togglePlay());
  }

  void _beginInteraction() {
    if (!_enabled) return;
    _interactionGeneration++;
    _overviewDragging = false;
    setState(() {
      _interacting = true;
      _dragOrigin = _position;
      _activeBoundary = null;
    });
  }

  void _beginOverviewInteraction() {
    if (!_enabled) return;
    _beginInteraction();
    setState(() {
      _overviewDragging = true;
      if (!_wantPlaying) _overviewReference ??= _position;
      _dragOrigin = _overviewReference ?? _position;
    });
  }

  void _beginBoundaryInteraction(int boundary) {
    _beginInteraction();
    if (!_interacting) return;
    setState(() => _activeBoundary = boundary);
    if (_wantPlaying) {
      // Keep the playback intent, but silence the actual player until release.
      _boundaryPauseTask = _player.pause().catchError((Object error) {
        if (mounted) {
          setState(() {
            _wantPlaying = false;
            _playOrigin = null;
          });
        }
        _message('暂停失败：$error');
      });
    }
  }

  void _endInteraction() {
    if (!mounted) return;
    final generation = _interactionGeneration;
    final overview = _overviewDragging;
    setState(() {
      _dragOrigin = null;
      _activeBoundary = null;
    });
    unawaited(_finishInteraction(generation, _boundaryPauseTask, overview));
  }

  Future<void> _finishInteraction(
    int generation,
    Future<void>? pauseTask,
    bool overview,
  ) async {
    try {
      await pauseTask;
      if (!mounted || generation != _interactionGeneration) return;
      if (_wantPlaying) {
        final s = _selection!;
        if (overview && _position >= s.endMs) {
          setState(() {
            _wantPlaying = false;
            _playOrigin = null;
          });
          await _player.pause();
          if (!mounted || generation != _interactionGeneration) return;
          _seek(s.endMs);
        } else if (!overview &&
            (_position >= s.endMs || _position < s.startMs)) {
          _seek(s.startMs);
        }
      }
      await _seekTask;
      if (!mounted || generation != _interactionGeneration) return;
      if (_wantPlaying && !_mediaBusy && !_player.playing) {
        unawaited(
          _player.play().catchError((Object error) {
            if (mounted) {
              setState(() {
                _wantPlaying = false;
                _playOrigin = null;
              });
            }
            _message('播放失败：$error');
          }),
        );
      }
      setState(() => _interacting = false);
      _boundaryPauseTask = null;
    } catch (error) {
      if (!mounted || generation != _interactionGeneration) return;
      setState(() {
        _interacting = false;
        _wantPlaying = false;
        _playOrigin = null;
      });
      _boundaryPauseTask = null;
      _message('恢复试听失败：$error');
    }
  }

  void _changeBoundary(int time, bool start) {
    if (!_enabled) return;
    final s = _selection!;
    final next = start ? s.withStart(time) : s.withEnd(time);
    setState(() => _selection = next);
    if (next.startMs > 0 || next.endMs < next.durationMs) {
      unawaited(_selectionHint());
    }
    if (_activeBoundary == null) {
      _seek(start ? next.startMs : next.endMs);
    }
  }

  void _seek(int position, {bool clearReference = false}) {
    if (_timeline == null || _mediaBusy || _exporting) return;
    _pendingSeek = position.clamp(0, _timeline!.durationMs);
    setState(() {
      _position = _pendingSeek!;
      if (clearReference) _overviewReference = null;
    });
    _seekTask ??= _drainSeeks();
  }

  Future<void> _drainSeeks() async {
    try {
      while (_pendingSeek != null && mounted) {
        var target = _pendingSeek!;
        _pendingSeek = null;
        if (_wantPlaying && _interacting && target == _timeline!.durationMs) {
          target = math.max(0, target - 1);
        }
        final location = _timeline!.locate(target);
        // No pause or source reload here: ExoPlayer keeps its playback state.
        await _player.seek(
          Duration(milliseconds: location.offsetMs),
          index: location.index,
        );
      }
    } catch (e) {
      if (mounted && _loopRestarting) {
        setState(() {
          _wantPlaying = false;
          _playOrigin = null;
        });
      }
      _message('定位失败：$e');
    } finally {
      _seekTask = null;
    }
  }

  Future<void> _togglePlay({bool ending = false}) async {
    if (!_enabled) return;
    setState(() {
      _transition = true;
      _endingPreview = ending;
      if (!_wantPlaying) _overviewReference = null;
    });
    try {
      if (_wantPlaying) {
        setState(() {
          _wantPlaying = false;
          _playOrigin = null;
        });
        await _player.pause();
      } else {
        final s = _selection!;
        if (_position < s.startMs || _position >= s.endMs) _seek(s.startMs);
        await _seekTask;
        if (!mounted) return;
        setState(() {
          _wantPlaying = true;
          _playOrigin = _position;
        });
        unawaited(
          _player.play().catchError((Object e) {
            if (mounted) {
              setState(() {
                _wantPlaying = false;
                _playOrigin = null;
              });
            }
            _message('播放失败：$e');
          }),
        );
      }
    } catch (e) {
      _message('试听失败：$e');
    } finally {
      if (mounted) setState(() => _transition = false);
    }
  }

  Future<void> _loadTimeline(AudioTimeline timeline, int position) async {
    if (timeline.isOriginal) {
      await _loadOriginal(initialPosition: Duration(milliseconds: position));
    } else {
      final location = timeline.locate(position);
      final source = ConcatenatingAudioSource(
        useLazyPreparation: false,
        children: timeline.spans
            .map(
              (span) => ClippingAudioSource(
                child: AudioSource.uri(_sourceUri),
                start: Duration(milliseconds: span.startMs),
                end: Duration(milliseconds: span.endMs),
              ),
            )
            .toList(),
      );
      await _player.setAudioSource(
        source,
        initialIndex: location.index,
        initialPosition: Duration(milliseconds: location.offsetMs),
      );
    }
  }

  Future<void> _edit({required bool remove}) async {
    if (!_enabled) return;
    final old = _EditSnapshot(_timeline!, _selection!, _position);
    final s = old.selection;
    final next = remove
        ? old.timeline.remove(s.startMs, s.endMs)
        : old.timeline.extract(s.startMs, s.endMs);
    await _apply(
      next,
      EditSelection.full(next.durationMs),
      remove ? math.min(s.startMs, next.durationMs) : 0,
      onSuccess: () {
        _history.add(old);
        _redoHistory.clear();
      },
    );
  }

  Future<void> _undo() async {
    if (!_enabled || _history.isEmpty) return;
    final old = _history.last;
    final current = _EditSnapshot(_timeline!, _selection!, _position);
    await _apply(
      old.timeline,
      old.selection,
      old.position,
      onSuccess: () {
        _history.removeLast();
        _redoHistory.add(current);
      },
    );
  }

  Future<void> _redo() async {
    if (!_enabled || _redoHistory.isEmpty) return;
    final next = _redoHistory.last;
    final current = _EditSnapshot(_timeline!, _selection!, _position);
    await _apply(
      next.timeline,
      next.selection,
      next.position,
      onSuccess: () {
        _redoHistory.removeLast();
        _history.add(current);
      },
    );
  }

  Future<void> _apply(
    AudioTimeline next,
    EditSelection selection,
    int position, {
    required VoidCallback onSuccess,
  }) async {
    final old = _EditSnapshot(_timeline!, _selection!, _position);
    setState(() {
      _mediaBusy = true;
      _wantPlaying = false;
      _playOrigin = null;
      _dragOrigin = null;
    });
    try {
      await _seekTask;
      await _player.pause();
      await _loadTimeline(next, position);
      if (!mounted) return;
      setState(() {
        _timeline = next;
        _selection = selection;
        _position = position;
        _overviewReference = null;
        _windowMs = _windowMs.clamp(
          math.min(500, next.durationMs),
          math.max(6000, next.durationMs * 2),
        );
        onSuccess();
      });
    } catch (e) {
      _message('编辑失败，已保留上一步内容：$e');
      try {
        await _loadTimeline(old.timeline, old.position);
      } catch (restoreError) {
        _message('恢复试听失败，请返回重新打开：$restoreError');
      }
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  bool get _hasUnsavedChanges =>
      _timeline != null &&
      _savedTimeline != null &&
      (!_timeline!.sameContent(_savedTimeline!) ||
          _fadeInMs != _savedFadeInMs ||
          _fadeOutMs != _savedFadeOutMs);

  Future<void> _requestLeave() async {
    if (_exporting || _mediaBusy || _leaveDialogOpen) return;
    if (_hasUnsavedChanges) {
      _leaveDialogOpen = true;
      setState(() {
        _wantPlaying = false;
        _playOrigin = null;
      });
      try {
        await _player.pause();
      } catch (_) {}
      if (!mounted) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('还有未保存的修改'),
          content: const Text('离开后，这次剪辑结果将不会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: editorRed),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      _leaveDialogOpen = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (!_enabled) return;
    setState(() {
      _wantPlaying = false;
      _playOrigin = null;
    });
    try {
      await _player.pause();
    } catch (error) {
      _message('暂停失败：$error');
      return;
    }
    if (!mounted) return;
    final options = await showDialog<SaveRingtoneOptions>(
      context: context,
      builder: (_) => SaveRingtoneDialog(
        path: widget.filePath,
        name: _exportName ?? _fileName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        timeline: _timeline!,
        selection: _selection!,
        fadeInMs: _fadeInMs,
        fadeOutMs: _fadeOutMs,
      ),
    );
    if (options == null || !mounted) return;
    final timeline = options.resolve(_timeline!, _selection!);
    setState(() {
      _exporting = true;
      _exportName = options.name;
      _fadeInMs = options.fadeInMs;
      _fadeOutMs = options.fadeOutMs;
    });
    String? savedUri;
    try {
      savedUri = await _service.exportTimeline(
        widget.filePath,
        timeline.spans.map((span) => span.toExportRange()).toList(),
        options.name,
        fadeInMs: options.fadeInMs,
        fadeOutMs: options.fadeOutMs,
      );
      if (!mounted) return;
      setState(() {
        _savedTimeline = _timeline;
        _savedFadeInMs = options.fadeInMs;
        _savedFadeOutMs = options.fadeOutMs;
      });
    } catch (error) {
      _message('保存失败，可重试：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (savedUri == null || !mounted) return;
    final uri = savedUri;
    RingtoneInfo? item;
    try {
      item = (await _service.queryRingtones()).firstWhere((i) => i.uri == uri);
    } catch (_) {}
    if (!mounted) return;
    final openLibrary = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SavedRingtoneSheet(
        uri: uri,
        name:
            item?.name ??
            (options.name.endsWith('.m4a')
                ? options.name
                : '${options.name}.m4a'),
        durationMs: item?.duration ?? timeline.durationMs,
      ),
    );
    if (openLibrary == true && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => HistoryPage(highlightUri: uri)),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _wantPlaying = false;
        _playOrigin = null;
      });
      unawaited(_player.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_service.cancelAnalysis(_requestId).catchError((Object _) {}));
    unawaited(_player.dispose());
    super.dispose();
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final active = action != null;
    return Tooltip(
      message: label == '移除'
          ? '删除选区并拼接剩余部分'
          : label == '保留'
          ? '只保留选区，继续编辑'
          : label,
      child: Semantics(
        label: label,
        button: true,
        enabled: active,
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: primary ? 74 : 58,
                  height: primary ? 74 : 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary
                        ? editorGreen
                        : active
                        ? Colors.white
                        : const Color(0xFFE1E3E6),
                  ),
                  child: primary
                      ? Icon(icon, size: 36, color: Colors.white)
                      : Center(
                          child: RecorderActionIcon(
                            extract: label == '保留',
                            color: active
                                ? Colors.black
                                : const Color(0xFF9EA1A5),
                            background: active
                                ? Colors.white
                                : const Color(0xFFE1E3E6),
                          ),
                        ),
                ),
                if (!primary) ...[
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? Colors.black : const Color(0xFFA3A6A9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionSummary(EditSelection selection) {
    Widget boundary(bool start) => Expanded(
      child: TextButton(
        key: ValueKey(start ? 'adjust-start' : 'adjust-end'),
        onPressed: _enabled ? () => _adjustBoundary(start) : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 36),
          foregroundColor: const Color(0xFF666A6E),
        ),
        child: Text(
          '${start ? '起点' : '终点'} ${displayTime(start ? selection.startMs : selection.endMs, fraction: true)}',
          style: const TextStyle(
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(children: [boundary(true), boundary(false)]),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  '已选 ${selectionLength(selection.endMs - selection.startMs)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777A7D),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                key: const ValueKey('loop-selection'),
                tooltip: _loopSelection ? '关闭循环试听' : '循环试听选区',
                isSelected: _loopSelection,
                onPressed: _enabled
                    ? () => setState(() => _loopSelection = !_loopSelection)
                    : null,
                icon: Icon(
                  Icons.repeat_rounded,
                  size: 20,
                  color: _loopSelection ? editorBlue : const Color(0xFF777A7D),
                ),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              TextButton.icon(
                key: const ValueKey('audition-ending'),
                onPressed: _enabled ? _previewEnding : null,
                icon: const Icon(Icons.last_page_rounded, size: 20),
                label: const Text('试听结尾', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF777A7D),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline, s = _selection;
    final partial = s != null && (s.startMs > 0 || s.endMs < s.durationMs);
    final name = _fileName;
    return PopScope(
      canPop: !_exporting && !_mediaBusy && (_allowPop || !_hasUnsavedChanges),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_exporting && !_mediaBusy) unawaited(_requestLeave());
      },
      child: Scaffold(
        backgroundColor: editorBackground,
        appBar: AppBar(
          backgroundColor: editorBackground,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 64,
          titleSpacing: 4,
          leading: TextButton(
            onPressed: _exporting || _mediaBusy ? null : _requestLeave,
            child: const Text(
              '取消',
              style: TextStyle(color: editorGreen, fontSize: 17),
            ),
          ),
          centerTitle: true,
          title: const Text(
            '裁切铃声',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          actions: [
            if (_history.isNotEmpty)
              IconButton(
                onPressed: _enabled ? _undo : null,
                tooltip: '撤销上次编辑',
                icon: const Icon(Icons.undo, color: editorGreen),
              ),
            if (_redoHistory.isNotEmpty)
              IconButton(
                onPressed: _enabled ? _redo : null,
                tooltip: '重做上次编辑',
                icon: const Icon(Icons.redo, color: editorGreen),
              ),
            TextButton(
              onPressed: _enabled ? _save : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.black,
                disabledForegroundColor: const Color(0xFFA3A6A9),
              ),
              child: const Text('保存', style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!),
                ),
              )
            : timeline == null || s == null
            ? const Center(child: CircularProgressIndicator(color: editorGreen))
            : SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final content = Column(
                      children: [
                        const SizedBox(height: 24),
                        Expanded(
                          flex: 4,
                          child: DetailWaveform(
                            timeline: timeline,
                            peaks: _waveform?.peaks ?? const [],
                            envelope: _waveform,
                            startMs: s.startMs,
                            endMs: s.endMs,
                            positionMs: _position,
                            windowMs: _windowMs,
                            dragOriginMs: _dragOrigin,
                            playOriginMs: _playOrigin,
                            activeBoundary: _activeBoundary,
                            onBoundaryDragStart: _beginBoundaryInteraction,
                            onPositionMenuRequested: _enabled && !_interacting
                                ? _showPositionMenu
                                : null,
                            onTogglePlayback: _enabled && !_interacting
                                ? _toggleFromWaveform
                                : null,
                            enabled: _enabled,
                            onStart: (v) => _changeBoundary(v, true),
                            onEnd: (v) => _changeBoundary(v, false),
                            onSeek: (v) => _seek(v, clearReference: true),
                            onZoom: (v) => setState(
                              () => _windowMs = v.clamp(
                                math.min(500, timeline.durationMs),
                                math.max(6000, timeline.durationMs * 2),
                              ),
                            ),
                            onInteractionStart: _beginInteraction,
                            onInteractionEnd: _endInteraction,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FittedBox(
                                  child: Text(
                                    displayTime(_position, fraction: true),
                                    style: const TextStyle(
                                      fontSize: 54,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                TailFilename(
                                  name: name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_waveLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 12),
                                    child: Text(
                                      '正在生成波形…',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (_waveError != null)
                                  Text(
                                    _waveError!,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _selectionSummary(s),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: OverviewWaveform(
                            timeline: timeline,
                            peaks: _waveform?.peaks ?? const [],
                            envelope: _waveform,
                            startMs: s.startMs,
                            endMs: s.endMs,
                            positionMs: _position,
                            referenceMs: _overviewReference,
                            playing: _wantPlaying,
                            enabled: _enabled,
                            onStart: (v) => _changeBoundary(v, true),
                            onEnd: (v) => _changeBoundary(v, false),
                            onInteractionStart: _beginOverviewInteraction,
                            onInteractionEnd: _endInteraction,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 3, 16, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                displayTime(_position),
                                style: const TextStyle(
                                  color: Color(0xFF777A7D),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                displayTime(timeline.durationMs),
                                style: const TextStyle(
                                  color: Color(0xFF777A7D),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 108,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _action(
                                '移除',
                                Icons.delete_outline,
                                _enabled && partial
                                    ? () => _edit(remove: true)
                                    : null,
                              ),
                              _action(
                                _wantPlaying ? '暂停' : '播放',
                                _wantPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                _enabled ? _togglePlay : null,
                                primary: true,
                              ),
                              _action(
                                '保留',
                                Icons.crop,
                                _enabled && partial
                                    ? () => _edit(remove: false)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                    return Stack(
                      children: [
                        if (constraints.maxHeight < 580)
                          SingleChildScrollView(
                            child: SizedBox(height: 660, child: content),
                          )
                        else
                          content,
                        if (_mediaBusy || _exporting)
                          Positioned.fill(
                            child: ColoredBox(
                              color: editorBackground.withValues(alpha: .85),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: editorGreen,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(_exporting ? '正在保存…' : '正在更新音频…'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}
