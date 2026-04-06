import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'editor_page.dart';
import 'history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [Permission.audio, Permission.videos, Permission.storage].request();
    }
  }

  Future<void> _pickFile() async {
    setState(() => _isLoading = true);

    try {
      await _requestPermissions();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mov',
          'avi',
          'mkv',
          'flv',
          'webm',
          'wmv',
          '3gp',
          'mp3',
          'wav',
          'flac',
          'aac',
          'ogg',
          'm4a',
          'wma',
          'amr',
        ],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final extension = filePath.split('.').last.toLowerCase();
        final isVideo = [
          'mp4',
          'mov',
          'avi',
          'mkv',
          'flv',
          'webm',
          'wmv',
          '3gp',
        ].contains(extension);

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                EditorPage(filePath: filePath, isVideo: isVideo),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('铃声制作'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
            tooltip: '我的铃声',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.music_note,
                size: 120,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 48),
              Text(
                '将视频/音频制作成铃声',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '支持 MP4, MOV, AVI, MKV,\nMP3, WAV, AAC 等格式',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 64),
              FilledButton.icon(
                onPressed: _isLoading ? null : _pickFile,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(_isLoading ? '加载中...' : '选择文件'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
