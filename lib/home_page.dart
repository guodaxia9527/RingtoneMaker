import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'services/audio_service.dart';
import 'editor_page.dart';
import 'history_page.dart';
import 'app_theme.dart';
import 'about_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    const channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');
    if (await channel.invokeMethod<bool>('ensureStoragePermission') != true) {
      throw Exception('需要存储权限才能保存和管理铃声');
    }
  }

  Future<void> _openHistory() async {
    setState(() => _isLoading = true);
    try {
      await _requestPermissions();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const HistoryPage()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开铃声库失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() => _isLoading = true);

    try {
      await _requestPermissions();

      final result = await AudioService().pickSource();
      if (result != null) {
        final filePath = result['path'] as String;
        final name = result['name'] as String;
        final isVideo =
            (result['mime'] as String).startsWith('video/') ||
            [
              'mp4',
              'mov',
              'avi',
              'mkv',
              'flv',
              'webm',
              'wmv',
              '3gp',
            ].contains(name.split('.').last.toLowerCase());

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorPage(
              filePath: filePath,
              isVideo: isVideo,
              displayName: name,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('铃声制作'),
      actions: [
        IconButton(
          tooltip: '关于',
          onPressed: _isLoading
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
          icon: const Icon(Icons.info_outline),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '留住喜欢的声音',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '从音频或视频中，截取你喜欢的一段',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF777A7D)),
                ),
                const SizedBox(height: 44),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    backgroundColor: editorGreen,
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _isLoading ? '正在打开…' : '选择文件',
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                const SizedBox(height: 16),
                Tooltip(
                  message: '我的铃声',
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _openHistory,
                    icon: const Icon(Icons.library_music_outlined, size: 20),
                    label: const Text('我的铃声', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  '本地剪辑，原文件保留',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A9DA0)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
