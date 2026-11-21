import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../app_theme.dart';
import '../audio_timeline.dart';
import '../edit_selection.dart';
import '../export_options.dart';
import '../services/audio_service.dart';

class SaveRingtoneDialog extends StatefulWidget {
  final String path, name;
  final AudioTimeline timeline;
  final EditSelection selection;
  final int fadeInMs, fadeOutMs;
  final AudioPlayer Function()? createPlayer;
  const SaveRingtoneDialog({
    super.key,
    required this.path,
    required this.name,
    required this.timeline,
    required this.selection,
    this.fadeInMs = 0,
    this.fadeOutMs = 0,
    this.createPlayer,
  });
  @override
  State<SaveRingtoneDialog> createState() => _SaveRingtoneDialogState();
}

class _SaveRingtoneDialogState extends State<SaveRingtoneDialog>
    with WidgetsBindingObserver {
  final _service = AudioService();
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late bool _selectionOnly = _partial;
  late bool _fadeIn = widget.fadeInMs > 0, _fadeOut = widget.fadeOutMs > 0;
  late int _inDuration = widget.fadeInMs > 0 ? widget.fadeInMs : 200;
  late int _outDuration = widget.fadeOutMs > 0 ? widget.fadeOutMs : 200;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerState;
  String? _previewPath, _error;
  bool _busy = false,
      _playing = false,
      _ending = false,
      _disposed = false,
      _closing = false;
  int _generation = 0;
  bool get _partial =>
      widget.selection.startMs > 0 ||
      widget.selection.endMs < widget.timeline.durationMs;
  SaveRingtoneOptions get _options => SaveRingtoneOptions(
    _name.text.trim(),
    _selectionOnly,
    _fadeIn ? _inDuration : 0,
    _fadeOut ? _outDuration : 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _release(String path) async {
    try {
      await _service.releasePreview(path);
    } catch (_) {
      /* Native expiry also cleans orphaned previews. */
    }
  }

  Future<void> _stopPreview() async {
    _generation++;
    final player = _player, subscription = _playerState, path = _previewPath;
    _player = null;
    _playerState = null;
    _previewPath = null;
    if (!_disposed && mounted) {
      setState(() {
        _busy = false;
        _playing = false;
      });
    }
    // Silence playback before waiting for stream/resource teardown.
    try {
      await player?.pause();
    } catch (_) {}
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await player?.dispose();
    } catch (_) {}
    if (path != null) await _release(path);
  }

  void _change(VoidCallback change) {
    unawaited(_stopPreview());
    setState(() {
      change();
      _error = null;
    });
  }

  Future<void> _preview(bool ending) async {
    final samePlaying = _playing && _ending == ending;
    final stopping = _stopPreview();
    final generation = _generation;
    if (mounted && !_disposed && !_closing && !samePlaying) {
      setState(() {
        _busy = true;
        _ending = ending;
      });
    }
    await stopping;
    if (!mounted ||
        _disposed ||
        _closing ||
        samePlaying ||
        generation != _generation) {
      return;
    }
    final options = _options;
    final preview = EdgePreview.of(
      options.resolve(widget.timeline, widget.selection),
      ending: ending,
      fadeInMs: options.fadeInMs,
      fadeOutMs: options.fadeOutMs,
    );
    setState(() {
      _busy = true;
      _ending = ending;
      _error = null;
    });
    try {
      final path = await _service.preview(
        widget.path,
        preview.timeline.spans.map((s) => s.toExportRange()).toList(),
        fadeInMs: preview.fadeInMs,
        fadeOutMs: preview.fadeOutMs,
      );
      if (_disposed || !mounted || generation != _generation) {
        await _release(path);
        return;
      }
      _previewPath = path;
      final player = widget.createPlayer?.call() ?? AudioPlayer();
      _player = player;
      await player.setFilePath(path);
      if (_disposed || !mounted || generation != _generation) return;
      _playerState = player.playerStateStream.listen((state) {
        if (!mounted || _disposed || generation != _generation) return;
        if (state.processingState == ProcessingState.completed) {
          setState(() => _playing = false);
        }
      });
      setState(() {
        _busy = false;
        _playing = true;
      });
      unawaited(
        player.play().catchError((Object error) {
          if (mounted && !_disposed && generation == _generation) {
            unawaited(_stopPreview());
            setState(() => _error = '试听失败：$error');
          }
        }),
      );
    } catch (e) {
      if (mounted && !_disposed && generation == _generation) {
        await _stopPreview();
        if (mounted && !_disposed) setState(() => _error = '试听失败，可重试：$e');
      }
    }
  }

  Future<void> _finish({required bool save}) async {
    if (_closing || (save && !_formKey.currentState!.validate())) return;
    final result = save ? _options : null;
    setState(() => _closing = true);
    await _stopPreview();
    if (mounted) Navigator.pop(context, result);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stopPreview());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopPreview());
    _name.dispose();
    super.dispose();
  }

  Widget _fadeControl(bool incoming) {
    final enabled = incoming ? _fadeIn : _fadeOut;
    final duration = incoming ? _inDuration : _outDuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: ValueKey(incoming ? 'fade-in-switch' : 'fade-out-switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            incoming ? '淡入' : '淡出',
            style: const TextStyle(fontSize: 15),
          ),
          subtitle: Text(enabled ? (incoming ? '开头渐强' : '结尾渐弱') : '已关闭'),
          value: enabled,
          onChanged: _closing
              ? null
              : (v) => _change(() {
                  if (incoming) {
                    _fadeIn = v;
                  } else {
                    _fadeOut = v;
                  }
                }),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final ms in [200, 500, 1000])
                  ChoiceChip(
                    key: ValueKey('${incoming ? 'in' : 'out'}-$ms'),
                    showCheckmark: false,
                    label: Text(
                      '${ms / 1000 == 1 ? '1' : (ms / 1000).toStringAsFixed(1)} 秒',
                    ),
                    selected: duration == ms,
                    onSelected: _closing
                        ? null
                        : (_) => _change(() {
                            if (incoming) {
                              _inDuration = ms;
                            } else {
                              _outDuration = ms;
                            }
                          }),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _previewButton(bool ending) {
    final active = _ending == ending;
    return TextButton.icon(
      key: ValueKey(ending ? 'preview-tail' : 'preview-head'),
      onPressed: _busy || _closing ? null : () => _preview(ending),
      icon: Icon(
        active && _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        size: 20,
      ),
      label: Text(
        active && _busy
            ? '正在准备…'
            : active && _playing
            ? '停止试听'
            : ending
            ? '试听结尾'
            : '试听开头',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存铃声'),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('export-name'),
                controller: _name,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '文件名',
                  suffixText: '.m4a',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入文件名' : null,
              ),
              if (_partial)
                RadioGroup<bool>(
                  groupValue: _selectionOnly,
                  onChanged: (v) {
                    if (!_closing && v != null) {
                      _change(() => _selectionOnly = v);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        value: true,
                        title: Text(
                          '选中片段 · ${selectionLength(widget.selection.endMs - widget.selection.startMs)}',
                        ),
                        subtitle: Text(
                          '${displayTime(widget.selection.startMs, fraction: true)} — ${displayTime(widget.selection.endMs, fraction: true)}',
                        ),
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        value: false,
                        title: const Text('全部编辑结果'),
                        subtitle: Text(
                          selectionLength(widget.timeline.durationMs),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '全部内容 · ${selectionLength(widget.timeline.durationMs)}',
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('声音选项', style: TextStyle(fontSize: 15)),
                subtitle: Text(
                  _fadeIn || _fadeOut
                      ? '${[if (_fadeIn) '淡入', if (_fadeOut) '淡出'].join('、')}已开启'
                      : '淡入、淡出均关闭',
                  style: const TextStyle(fontSize: 12),
                ),
                children: [
                  _fadeControl(true),
                  _fadeControl(false),
                  const Text(
                    '短片段会自动缩短渐变时长',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              Wrap(
                spacing: 4,
                children: [_previewButton(false), _previewButton(true)],
              ),
              const Text(
                '试听前 / 后 3 秒，包含所选声音效果',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: editorRed, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _closing ? null : () => _finish(save: false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _closing ? null : () => _finish(save: true),
        child: const Text('保存'),
      ),
    ],
  );
}
