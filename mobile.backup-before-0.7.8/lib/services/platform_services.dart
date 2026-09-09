import 'package:flutter/services.dart';

class PlatformServices {
  static const _channel = MethodChannel('com.threadvault.app/platform');

  static Future<String?> publishDownload({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    return _channel.invokeMethod<String>('publishDownload', {
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  static Future<bool> isOnWifi() async {
    return (await _channel.invokeMethod<bool>('isOnWifi')) ?? false;
  }
}
