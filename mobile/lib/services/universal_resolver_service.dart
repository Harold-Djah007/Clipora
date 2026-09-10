import 'package:dio/dio.dart';
import '../models/media_models.dart';
import 'resolver_url.dart';
import 'universal_platform_detector.dart';

class UniversalResolverService {
  final Dio _dio;
  String preferredBaseUrl;

  UniversalResolverService({Dio? dio, String? preferredBaseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 2),
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 180),
              validateStatus: (code) => code != null && code >= 200 && code < 500,
              headers: const {'Content-Type': 'application/json'},
            )),
        preferredBaseUrl = preferredBaseUrl ?? ResolverUrl.defaultValue;

  List<String> get baseUrls => ResolverUrl.candidates(preferredBaseUrl);

  bool get hasConfiguredBackend => baseUrls.isNotEmpty;

  Future<String> ping() async {
    if (baseUrls.isEmpty) {
      throw StateError('No Clipora resolver is configured. Add a hosted resolver URL or build with CLIPORA_RESOLVER_URL.');
    }

    Object? lastError;
    for (final baseUrl in baseUrls) {
      try {
        final response = await _dio.get(
          '$baseUrl/api/health',
          options: Options(
            connectTimeout: const Duration(seconds: 2),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        if (response.statusCode == 200) return baseUrl;
      } on DioException catch (error) {
        lastError = error;
      }
    }
    throw StateError('Clipora resolver is not reachable. Last error: ${_shortError(lastError)}');
  }

  Future<ResolvedPost> resolve(String url) async {
    final platform = UniversalPlatformDetector.detect(url);
    if (!platform.isSupported) {
      throw StateError('Unsupported link. Clipora supports ${UniversalPlatformDetector.supportedLabel}.');
    }
    if (baseUrls.isEmpty) {
      throw StateError('No Clipora resolver is configured.');
    }

    Object? lastError;
    for (final baseUrl in baseUrls) {
      try {
        final response = await _dio.post('$baseUrl/api/resolve/universal', data: {'url': url});
        final data = response.data;
        if (response.statusCode == 200 && data is Map) {
          return postFromJson(Map<String, dynamic>.from(data), fallbackUrl: url, baseUrl: baseUrl);
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

    throw StateError('Clipora resolver is not reachable. Last error: ${_shortError(lastError)}');
  }

  static ResolvedPost postFromJson(
    Map<String, dynamic> json, {
    required String fallbackUrl,
    String? baseUrl,
  }) {
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
          url: _absolutize(url.trim(), baseUrl),
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

  static String _absolutize(String url, String? baseUrl) {
    if (baseUrl != null && url.startsWith('/')) return '$baseUrl$url';
    return url;
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
