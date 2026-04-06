import 'package:flutter/services.dart';

enum RingtoneType {
  ringtone, // 来电铃声
  alarm, // 闹钟铃声
  notification, // 通知铃声
}

class RingtoneService {
  static const MethodChannel _channel = MethodChannel(
    'com.ringtone.ringtone_maker/ringtone',
  );

  Future<bool> hasWriteSettingsPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasWriteSettingsPermission',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestWriteSettingsPermission() async {
    try {
      await _channel.invokeMethod('requestWriteSettingsPermission');
    } on PlatformException catch (e) {
      throw Exception('Failed to request permission: ${e.message}');
    }
  }

  Future<bool> setAsRingtone(String path, RingtoneType type) async {
    try {
      final result = await _channel.invokeMethod<bool>('setAsRingtone', {
        'path': path,
        'type': type.index,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Failed to set ringtone: ${e.message}');
    }
  }

  String getRingtoneTypeName(RingtoneType type) {
    switch (type) {
      case RingtoneType.ringtone:
        return '来电铃声';
      case RingtoneType.alarm:
        return '闹钟铃声';
      case RingtoneType.notification:
        return '通知铃声';
    }
  }
}
