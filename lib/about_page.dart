import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'services/app_info_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _wechat = 'GuoDaXia_Tools';
  late final Future<AppInfo> _info = AppInfoService().load();

  Future<void> _copyWechat() async {
    try {
      await Clipboard.setData(const ClipboardData(text: _wechat));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('微信号已复制')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
    }
  }

  void _showSupport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _SupportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: FutureBuilder<AppInfo>(
              future: _info,
              builder: (context, snapshot) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        AppInfoService.iconAsset,
                        width: 88,
                        height: 88,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '大侠铃声制作',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    snapshot.hasData
                        ? '版本 ${snapshot.data!.label}'
                        : snapshot.hasError
                        ? '版本信息暂不可用'
                        : '正在读取版本…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: _secondary),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '留住喜欢的声音',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: _secondary),
                  ),
                  const SizedBox(height: 28),
                  const _AboutCard(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _CreditRow(label: '作者', value: '锅大侠'),
                          SizedBox(height: 18),
                          _CreditRow(
                            label: 'AI 协作',
                            value: 'GPT-6 Astra Extra High',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AboutCard(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '反馈与建议',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '微信：$_wechat',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _secondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _copyWechat,
                                style: TextButton.styleFrom(
                                  foregroundColor: editorBlue,
                                ),
                                child: const Text('复制'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AboutCard(
                    child: InkWell(
                      onTap: _showSupport,
                      child: const Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.local_cafe_outlined, size: 24),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '请作者喝杯茶',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    '自愿支持，感谢鼓励',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: _secondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '本地剪辑，原文件保留',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _secondary),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: '大侠铃声制作',
                        applicationVersion: snapshot.data?.label,
                        applicationIcon: Image.asset(
                          AppInfoService.iconAsset,
                          width: 48,
                          height: 48,
                          excludeFromSemantics: true,
                        ),
                      ),
                      style: TextButton.styleFrom(foregroundColor: _secondary),
                      child: const Text('开源许可', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _secondary = Color(0xFF777A7D);

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 74,
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: _secondary),
        ),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );
}

class _SupportSheet extends StatefulWidget {
  const _SupportSheet();

  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  bool _saving = false;
  bool _saved = false;
  String? _error;

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppInfoService().saveSupportQr();
      if (mounted) setState(() => _saved = true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'STORAGE_PERMISSION_DENIED'
            ? '保存图片需要存储权限，请授权后重试'
            : '保存失败，请重试';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '支持作者',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '自愿支持，感谢鼓励',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _secondary),
              ),
              const SizedBox(height: 20),
              Image.asset(
                AppInfoService.supportQrAsset,
                fit: BoxFit.contain,
                semanticLabel: '锅大侠的微信赞赏码',
              ),
              const SizedBox(height: 16),
              const Text(
                '保存后可在微信扫一扫中从相册选择',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _secondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: editorRed),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving || _saved ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_saved ? Icons.check : Icons.save_alt),
                label: Text(
                  _saving
                      ? '正在保存…'
                      : _saved
                      ? '已保存到相册'
                      : '保存到相册',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
