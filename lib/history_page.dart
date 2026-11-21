import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'app_theme.dart';
import 'audio_timeline.dart';
import 'services/audio_service.dart';
import 'services/ringtone_actions.dart';
import 'widgets/tail_filename.dart';

class HistoryPage extends StatefulWidget {
  final String? highlightUri;
  final AudioPlayer? player;
  const HistoryPage({super.key, this.highlightUri, this.player});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with WidgetsBindingObserver {
  final _service = AudioService();
  late final _player = widget.player ?? AudioPlayer();
  late final _actions = RingtoneActions(onMessage: _message)
    ..addListener(_refresh);
  List<RingtoneInfo> _items = [];
  String? _current, _error;
  bool _loading = true, _localBusy = false;
  int _loadVersion = 0;
  StreamSubscription<PlayerState>? _subscription;
  bool get _busy => _localBusy || _actions.busy;
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
    unawaited(_load());
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.queryRingtones();
      if (mounted && version == _loadVersion) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loading = false;
          _error = '读取铃声失败：$error';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _localBusy = true);
    try {
      await action();
    } catch (error) {
      _message('操作失败：$error');
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _toggle(String uri) => _run(() async {
    if (_current == uri && _player.playing) {
      await _player.pause();
    } else {
      if (_current != uri) {
        await _player.setUrl(uri);
        if (!mounted) return;
        setState(() => _current = uri);
      } else if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      if (mounted) {
        unawaited(_player.play().catchError((Object e) => _message('播放失败：$e')));
      }
    }
  });
  Future<void> _action(RingtoneInfo item, String action) async {
    if (_busy) return;
    if (action == 'ringtone') {
      await _player.pause();
      if (!mounted) return;
      final type = await chooseRingtoneType(context);
      if (type != null && mounted) await _actions.setAsRingtone(item.uri, type);
    } else if (action == 'share') {
      await _player.pause();
      if (mounted) await _actions.share(item.uri, item.name);
    } else if (action == 'rename') {
      final controller = TextEditingController(
        text: item.name.replaceFirst(RegExp(r'\.m4a$'), ''),
      );
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: '文件名',
              suffixText: '.m4a',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        controller.dispose,
      );
      if (name != null && mounted) {
        await _run(() async {
          await _service.renameRingtone(item.uri, name);
          await _load();
        });
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这段铃声？'),
          content: Text(item.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: editorRed),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await _run(() async {
          if (_current == item.uri) {
            await _player.stop();
            _current = null;
          }
          if (!await _service.deleteRingtone(item.uri)) {
            throw Exception('文件未删除');
          }
          await _load();
        });
      }
    }
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

  String _date(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('我的铃声'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.library_music_outlined,
                        size: 42,
                        color: Color(0xFFB7BBBD),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '还没有铃声',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '剪辑并保存后，会显示在这里',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.popUntil(
                          context,
                          (route) => route.isFirst,
                        ),
                        child: const Text('返回选择文件'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (context, index) {
                      final item = _items[index],
                          current = item.uri == _current;
                      final playing =
                          current &&
                          _player.playing &&
                          _player.processingState != ProcessingState.completed;
                      return Container(
                        decoration: BoxDecoration(
                          color: item.uri == widget.highlightUri
                              ? editorGreen.withValues(alpha: .07)
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Material(
                                  color: current ? editorGreen : Colors.white,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    onTap: _busy
                                        ? null
                                        : () => _toggle(item.uri),
                                    customBorder: const CircleBorder(),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Icon(
                                        playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: current
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TailFilename(
                                        name: item.name,
                                        textAlign: TextAlign.left,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${displayTime(item.duration)}${item.createdAt == 0 ? '' : ' · ${_date(item.createdAt)}'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8B8F92),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  enabled: !_busy,
                                  tooltip: '更多操作',
                                  icon: const Icon(Icons.more_horiz),
                                  onSelected: (action) => _action(item, action),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'ringtone',
                                      child: Text('设为铃声'),
                                    ),
                                    PopupMenuItem(
                                      value: 'share',
                                      child: Text('分享'),
                                    ),
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (current)
                              StreamBuilder<Duration>(
                                stream: _player.positionStream,
                                builder: (context, snapshot) {
                                  final max =
                                      _player.duration?.inMilliseconds ??
                                      (item.duration > 0 ? item.duration : 1);
                                  return Slider(
                                    value: (snapshot.data?.inMilliseconds ?? 0)
                                        .clamp(0, max)
                                        .toDouble(),
                                    max: max.toDouble(),
                                    onChanged: _busy
                                        ? null
                                        : (v) => _player.seek(
                                            Duration(milliseconds: v.round()),
                                          ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
