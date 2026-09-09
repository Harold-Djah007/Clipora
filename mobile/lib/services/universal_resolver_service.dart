import 'package:dio/dio.dart';
import '../models/media_models.dart';
import 'universal_platform_detector.dart';

class UniversalResolverService {
  final Dio _dio;
  final List<String> baseUrls;

  UniversalResolverService({Dio? dio, List<String>? baseUrls})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 45),
              validateStatus: (code) => code != null && code >= 200 && code < 500,
              headers: const {'Content-Type': 'application/json'},
            )),
        baseUrls = baseUrls ??
            const [
              'http://127.0.0.1:8010',
              'http://127.0.0.1:8011',
              'http://127.0.0.1:8765',
              'http://10.0.2.2:8010',
            ];

  Future<PlatformMatch> detect(String url) async {
    final local = UniversalPlatformDetector.detect(url);
    if (!local.isSupported) return local;

    for (final baseUrl in baseUrls) {
      try {
        final response = await _dio.post('$baseUrl/api/detect', data: {'url': url});
        final data = response.data;
        if (response.statusCode == 200 && data is Map) {
          return UniversalPlatformDetector.detect(url);
        }
      } catch (_) {
        // Local detector is enough for the UI. Network failure is handled by resolve().
      }
    }
    return local;
  }

  Future<ResolvedPost> resolve(String url) async {
    final platform = UniversalPlatformDetector.detect(url);
    if (!platform.isSupported) {
      throw StateError('Unsupported link. Clipora supports ${UniversalPlatformDetector.supportedLabel}.');
    }

    Object? lastError;
    for (final baseUrl in baseUrls) {
      try {
        final response = await _dio.post('$baseUrl/api/resolve/universal', data: {'url': url});
        final data = response.data;
        if (response.statusCode == 200 && data is Map<String, dynamic>) {
          return postFromJson(data, fallbackUrl: url);
        }
        if (response.statusCode != null && response.statusCode! >= 400) {
          throw StateError(_extractBackendError(data, response.statusCode));
        }
      } on DioException catch (error) {
        if (error.response != null) {
          throw StateError(_extractBackendError(error.response?.data, error.response?.statusCode));
        }
        lastError = error;
      }
    }

    throw StateError(
      'Clipora backend is not reachable. Keep backend running, then run: adb reverse tcp:8010 tcp:8010. Last error: ${_shortError(lastError)}',
    );
  }

  static ResolvedPost postFromJson(Map<String, dynamic> json, {required String fallbackUrl}) {
    final rawMedia = json['media'];
    if (rawMedia is! List) {
      throw const FormatException('Universal resolver returned no media list.');
    }

    final media = <ResolvedMedia>[];
    for (final entry in rawMedia) {
      if (entry is! Map) continue;
      final url = entry['url'];
      if (url is! String || url.trim().isEmpty) continue;
      final type = '${entry['media_type'] ?? entry['type'] ?? 'video'}'.toLowerCase();
      final kind = type.contains('image') || type.contains('photo') ? MediaKind.image : MediaKind.video;
      media.add(
        ResolvedMedia(
          kind: kind,
          url: url,
          width: _asInt(entry['width']),
          height: _asInt(entry['height']),
          mimeType: entry['mime_type'] as String? ?? (kind == MediaKind.video ? 'video/mp4' : 'image/jpeg'),
        ),
      );
    }

    if (media.isEmpty) {
      throw const FormatException('Universal resolver found the post but returned no downloadable media.');
    }

    return ResolvedPost(
      sourceUrl: (json['source_url'] as String?) ?? fallbackUrl,
      postId: _safePart((json['post_id'] ?? json['id'])?.toString(), fallback: 'clipora'),
      author: _safePart((json['author'] ?? json['platform'])?.toString(), fallback: 'clipora'),
      caption: (json['caption'] ?? json['title'])?.toString(),
      media: media,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _safePart(String? raw, {required String fallback}) {
    final cleaned = (raw ?? fallback).replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^[_\.-]+|[_\.-]+$'), '');
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  static String _extractBackendError(Object? data, int? statusCode) {
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (data is String && data.trim().isNotEmpty) return data;
    return 'Backend resolver returned HTTP ${statusCode ?? 'error'}.';
  }

  static String _shortError(Object? error) {
    if (error == null) return 'unknown';
    final text = error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }
}
