import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../app_theme.dart';
import '../audio_timeline.dart';
import '../services/ringtone_actions.dart';
import 'tail_filename.dart';

class SavedRingtoneSheet extends StatefulWidget {
  final String uri, name;
  final int durationMs;
  final AudioPlayer? player;
  const SavedRingtoneSheet({
    super.key,
    required this.uri,
    required this.name,
    required this.durationMs,
    this.player,
  });
  @override
  State<SavedRingtoneSheet> createState() => _SavedRingtoneSheetState();
}

class _SavedRingtoneSheetState extends State<SavedRingtoneSheet>
    with WidgetsBindingObserver {
  late final _player = widget.player ?? AudioPlayer();
  late final _actions = RingtoneActions(
    onMessage: (message) {
      if (mounted) setState(() => _status = message);
    },
  )..addListener(_refresh);
  StreamSubscription<PlayerState>? _subscription;
  bool _loaded = false, _loading = false;
  String? _status;
  bool get _busy => _loading || _actions.busy;
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        unawaited(_player.pause());
      }
      setState(() {});
    });
  }

  Future<void> _preview() async {
    if (_busy) return;
    setState(() => _loading = true);
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        if (!_loaded) {
          await _player.setUrl(widget.uri);
          _loaded = true;
        } else if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        if (mounted) {
          unawaited(
            _player.play().catchError((Object error) {
              if (mounted) setState(() => _status = '试听失败：$error');
            }),
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = '试听失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRingtone() async {
    await _player.pause();
    if (!mounted) return;
    final type = await chooseRingtoneType(context);
    if (type != null && mounted) await _actions.setAsRingtone(widget.uri, type);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actions.dispose();
    unawaited(_subscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, color: editorGreen, size: 46),
          const SizedBox(height: 12),
          const Text(
            '铃声已保存',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TailFilename(
            name: widget.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            '${displayTime(widget.durationMs)} · Download/RingtoneMaker',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF85898D)),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _status!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _setRingtone,
            icon: const Icon(Icons.call_outlined),
            label: const Text('设为铃声'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy ? null : _preview,
                  icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
                  label: Text(_player.playing ? '暂停' : '试听'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _player.pause();
                          if (mounted) {
                            await _actions.share(widget.uri, widget.name);
                          }
                        },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('分享'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, true),
            child: const Text('查看我的铃声'),
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
