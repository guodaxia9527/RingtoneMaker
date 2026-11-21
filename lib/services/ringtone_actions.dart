import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'audio_service.dart';
import 'ringtone_service.dart';

/// Owns the pending system-settings round trip for one visible page or sheet.
class RingtoneActions extends ChangeNotifier with WidgetsBindingObserver {
  final void Function(String) onMessage;
  final _ringtone = RingtoneService();
  final _audio = AudioService();
  bool busy = false, _alive = true;
  (String, RingtoneType)? _pending;
  RingtoneActions({required this.onMessage}) {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _run(Future<void> Function() task) async {
    if (busy || !_alive) return;
    busy = true;
    notifyListeners();
    try {
      await task();
    } catch (error) {
      if (_alive) onMessage('操作失败：$error');
    } finally {
      busy = false;
      if (_alive) notifyListeners();
    }
  }

  Future<void> share(String uri, String name) => _run(() async {
    final path = await _audio.shareCopy(uri);
    if (_alive) await Share.shareXFiles([XFile(path)], text: name);
  });

  Future<void> setAsRingtone(String uri, RingtoneType type) => _run(() async {
    if (!await _ringtone.hasWriteSettingsPermission()) {
      if (!_alive) return;
      _pending = (uri, type);
      onMessage('请允许修改系统设置，返回后会继续设置');
      try {
        await _ringtone.requestWriteSettingsPermission();
      } catch (_) {
        _pending = null;
        rethrow;
      }
      return;
    }
    if (!_alive) return;
    if (!await _ringtone.setAsRingtone(uri, type)) throw Exception('设置铃声失败');
    if (_alive) onMessage('已设为${_ringtone.getRingtoneTypeName(type)}');
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pending != null) {
      final pending = _pending!;
      _pending = null;
      _run(() async {
        final granted = await _ringtone.hasWriteSettingsPermission();
        if (!_alive) return;
        if (granted) {
          if (!await _ringtone.setAsRingtone(pending.$1, pending.$2)) {
            throw Exception("设置铃声失败");
          }
          if (_alive) {
            onMessage("已设为${_ringtone.getRingtoneTypeName(pending.$2)}");
          }
        } else {
          onMessage("未授予权限，可再次点击设为铃声");
        }
      });
    }
  }

  @override
  void dispose() {
    _alive = false;
    _pending = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

Future<RingtoneType?> chooseRingtoneType(BuildContext context) =>
    showModalBottomSheet<RingtoneType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                '设为铃声',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ),
            for (final entry in [
              (RingtoneType.ringtone, Icons.call_outlined, '来电铃声'),
              (RingtoneType.alarm, Icons.alarm, '闹钟铃声'),
              (RingtoneType.notification, Icons.notifications_none, '通知铃声'),
            ])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                leading: Icon(entry.$2, color: Colors.black),
                title: Text(entry.$3),
                onTap: () => Navigator.pop(context, entry.$1),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
