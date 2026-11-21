import 'package:flutter/services.dart';

class AppInfo {
  const AppInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label => buildNumber.isEmpty ? version : '$version（$buildNumber）';
}

class AppInfoService {
  static const iconAsset = 'assets/branding/icon_1a_white_blue.png';
  static const supportQrAsset = 'assets/support/wechat_reward.png';
  static const _channel = MethodChannel('com.ringtone.ringtone_maker/ringtone');

  Future<AppInfo> load() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('appInfo');
    final version = data?['versionName'] as String?;
    if (version == null || version.isEmpty) {
      throw const FormatException('版本信息不可用');
    }
    return AppInfo(
      version: version,
      buildNumber: data?['buildNumber']?.toString() ?? '',
    );
  }

  Future<void> saveSupportQr() async {
    if (await _channel.invokeMethod<bool>('ensureStoragePermission') != true) {
      throw PlatformException(code: 'STORAGE_PERMISSION_DENIED');
    }
    final image = await rootBundle.load(supportQrAsset);
    final uri = await _channel.invokeMethod<String>('saveSupportQr', {
      'bytes': image.buffer.asUint8List(
        image.offsetInBytes,
        image.lengthInBytes,
      ),
    });
    if (uri == null || uri.isEmpty) {
      throw PlatformException(code: 'SAVE_IMAGE_FAILED');
    }
  }
}
