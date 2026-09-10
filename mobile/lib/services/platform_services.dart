import 'package:flutter/foundation.dart';
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
    try {
      return (await _channel.invokeMethod<bool>('isOnWifi')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startDownloadService({
    String title = 'Clipora',
    String message = 'Downloading media…',
  }) async {
    try {
      await _channel.invokeMethod<void>('startDownloadService', {
        'title': title,
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> updateDownloadService({
    String title = 'Clipora',
    required String message,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateDownloadService', {
        'title': title,
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> showDownloadComplete({
    String title = 'Clipora',
    required String message,
    required bool success,
  }) async {
    try {
      await _channel.invokeMethod<void>('showDownloadComplete', {
        'title': title,
        'message': message,
        'success': success,
      });
    } catch (error) {
      debugPrint('[Clipora] could not show download notification: $error');
    }
  }

  static Future<void> stopDownloadService() async {
    try {
      await _channel.invokeMethod<void>('stopDownloadService');
    } catch (_) {}
  }

  static Future<void> returnToSourceApp() async {
    try {
      await _channel.invokeMethod<void>('returnToSourceApp');
    } catch (_) {}
  }

  static Future<String?> takeSharedUrl() async {
    try {
      final value = await _channel.invokeMethod<String>('takeSharedUrl');
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      return null;
    }
  }
}
