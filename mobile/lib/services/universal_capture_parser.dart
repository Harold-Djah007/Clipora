import 'dart:convert';

import '../models/media_models.dart';
import 'universal_platform_detector.dart';

class UniversalCaptureParser {
  ResolvedPost parse(String source, String postUrl, PlatformMatch platform) {
    final envelope = _decodeEnvelope(source);
    final normalized = _decodeHtml(envelope.html);
    final postId = _safePart(
      _postIdFromUrl(envelope.canonicalUrl ?? envelope.pageUrl ?? postUrl) ?? 'capture',
      fallback: 'capture',
    );
    final author = _safePart(
      _authorFromUrl(envelope.canonicalUrl ?? envelope.pageUrl ?? postUrl) ?? platform.label.toLowerCase(),
      fallback: platform.label.toLowerCase().replaceAll('/', '_'),
    );
    final media = <ResolvedMedia>[];
    final videoHint = envelope.hasVideoHint || _hasVideoHint(normalized);

    _extractRuntimeMedia(envelope.runtimeMedia, media);
    _extractDirectVideos(normalized, media);

    if (!media.any((item) => item.kind == MediaKind.video)) {
      if (videoHint) {
        throw FormatException(
          '${platform.label} opened, but the page only exposed a poster image so far. Play the video once in Smart Capture, then tap Capture again.',
        );
      }
      _extractImages(normalized, media);
    }

    final unique = <String, ResolvedMedia>{};
    for (final item in media) {
      final cleaned = _unescape(item.url);
      if (!_isAllowedCaptureMediaUrl(cleaned)) continue;
      unique[cleaned] = ResolvedMedia(
        kind: item.kind,
        url: cleaned,
        width: item.width,
        height: item.height,
        mimeType: item.mimeType,
      );
    }

    var values = unique.values.toList(growable: false);
    final videos = values.where((item) => item.kind == MediaKind.video).toList(growable: false);
    if (videos.isNotEmpty) {
      values = videos;
    }
    if (values.isEmpty) {
      throw FormatException(
        'No real ${platform.label} media was found in Smart Capture. Open the post, wait for it to load, play the video once, then tap Capture.',
      );
    }

    return ResolvedPost(
      sourceUrl: postUrl,
      postId: postId,
      author: author,
      caption: _extractCaption(normalized),
      media: values,
    );
  }

  _CaptureEnvelope _decodeEnvelope(String input) {
    final decodedInput = _decodeHtml(input);
    try {
      final decoded = jsonDecode(decodedInput);
      if (decoded is Map) {
        return _CaptureEnvelope(
          html: decoded['html'] is String ? decoded['html'] as String : decodedInput,
          pageUrl: decoded['pageUrl'] is String ? decoded['pageUrl'] as String : null,
          canonicalUrl: decoded['canonicalUrl'] is String ? decoded['canonicalUrl'] as String : null,
          runtimeMedia: _runtimeMedia(decoded['runtimeMedia']),
          hasVideoHint: decoded['hasVideo'] == true,
        );
      }
    } catch (_) {}
    return _CaptureEnvelope(html: decodedInput, runtimeMedia: const []);
  }

  List<_RuntimeMedia> _runtimeMedia(Object? raw) {
    if (raw is! List) return const [];
    final out = <_RuntimeMedia>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final kind = item['kind'];
      final url = item['url'];
      if (kind is! String || url is! String) continue;
      out.add(_RuntimeMedia(
        kind: kind,
        url: url,
        width: _asInt(item['width']),
        height: _asInt(item['height']),
      ));
    }
    return out;
  }

  void _extractRuntimeMedia(List<_RuntimeMedia> runtime, List<ResolvedMedia> out) {
    for (final item in runtime) {
      final url = _unescape(item.url);
      if (!_isAllowedCaptureMediaUrl(url)) continue;
      if (item.kind == 'video' && _looksLikeVideo(url)) {
        out.add(ResolvedMedia(
          kind: MediaKind.video,
          url: url,
          width: item.width,
          height: item.height,
          mimeType: 'video/mp4',
        ));
      } else if (item.kind == 'image' && _looksLikeImage(url)) {
        out.add(ResolvedMedia(
          kind: MediaKind.image,
          url: url,
          width: item.width,
          height: item.height,
          mimeType: _imageMime(url),
        ));
      }
    }
  }

  void _extractDirectVideos(String source, List<ResolvedMedia> out) {
    final patterns = [
      RegExp(r'"(?:video_url|playable_url|src)"\s*:\s*"([^"]+\.mp4[^"]*)"', caseSensitive: false),
      RegExp(r'''https?:\\?/\\?/[^"'<>\s]+?\.mp4[^"'<>\s]*''', caseSensitive: false),
      RegExp(r'''https?://[^"'<>\s]+?\.mp4[^"'<>\s]*''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final raw = match.groupCount > 0 ? match.group(1) : match.group(0);
        final url = _unescape(raw ?? '');
        if (_looksLikeVideo(url) && _isAllowedCaptureMediaUrl(url)) {
          out.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
        }
      }
    }
  }

  void _extractImages(String source, List<ResolvedMedia> out) {
    final patterns = [
      RegExp(r'"(?:display_url|image_url|thumbnail_url|og:image)"\s*:?\s*"([^"]+)"', caseSensitive: false),
      RegExp(r'''https?://[^"'<>\s]+?\.(?:jpe?g|png|webp)(?:\?[^"'<>\s]*)?''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final raw = match.groupCount > 0 ? match.group(1) : match.group(0);
        final url = _unescape(raw ?? '');
        if (_looksLikeImage(url) && _isAllowedCaptureMediaUrl(url)) {
          out.add(ResolvedMedia(kind: MediaKind.image, url: url, mimeType: _imageMime(url)));
        }
      }
    }
  }

  bool _hasVideoHint(String source) {
    final lower = source.toLowerCase();
    return lower.contains('video_url') ||
        lower.contains('playable_url') ||
        lower.contains('video_versions') ||
        lower.contains('<video') ||
        lower.contains('.mp4') ||
        lower.contains('mime_type=video');
  }

  bool _isAllowedCaptureMediaUrl(String url) {
    if (!_isHttp(url) || url.startsWith('blob:')) return false;
    final lower = url.toLowerCase();
    if (lower.contains('/rsrc.php/') || lower.contains('/static/')) return false;
    if (lower.contains('sprite') || lower.contains('favicon') || lower.contains('profile_pic')) return false;
    if (lower.endsWith('.css') || lower.endsWith('.js') || lower.endsWith('.svg')) return false;
    if (_looksLikeAudio(lower)) return false;
    return _looksLikeVideo(url) || _looksLikeImage(url);
  }

  bool _looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return _isHttp(url) &&
        !_looksLikeAudio(lower) &&
        (lower.contains('.mp4') || lower.contains('mime_type=video'));
  }

  bool _looksLikeImage(String url) {
    final lower = url.toLowerCase();
    return _isHttp(url) &&
        (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp'));
  }

  bool _looksLikeAudio(String lower) {
    return lower.contains('mime_type=audio') ||
        lower.contains('/audio/') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg');
  }

  String? _extractCaption(String source) {
    final patterns = [
      RegExp(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"', caseSensitive: false),
      RegExp(r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"(.*?)"', dotAll: true),
      RegExp(r'"description"\s*:\s*"(.*?)"', dotAll: true),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      final text = _unescape(match.group(1) ?? '').trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String? _postIdFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    final parts = parsed.pathSegments.where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (parts.isEmpty) return null;
    for (var i = 0; i < parts.length - 1; i++) {
      final marker = parts[i].toLowerCase();
      if (marker == 'reel' || marker == 'p' || marker == 'tv' || marker == 'videos' || marker == 'video') {
        return parts[i + 1];
      }
    }
    return parts.last;
  }

  String? _authorFromUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.pathSegments.isEmpty) return null;
    final first = parsed.pathSegments.first;
    if (first == 'reel' || first == 'p' || first == 'tv' || first == 'watch' || first == 'share') return null;
    return first.startsWith('@') ? first.substring(1) : first;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }

  String _safePart(String? raw, {required String fallback}) {
    final value = (raw ?? fallback)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^[_\.-]+|[_\.-]+$'), '');
    if (value.isEmpty) return fallback;
    return value.length > 80 ? value.substring(0, 80) : value;
  }

  String _imageMime(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'image/png';
    if (lower.contains('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  bool _isHttp(String value) => value.startsWith('https://') || value.startsWith('http://');

  String _decodeHtml(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x2F;', '/');

  String _unescape(String input) {
    var value = input
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u00253D', '%3D')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003F', '?')
        .replaceAll(r'\u0025', '%')
        .replaceAll(r'\u002F', '/')
        .replaceAll(r'\u003A', ':')
        .replaceAll(r'\u002D', '-')
        .replaceAll('&amp;', '&');
    try {
      value = jsonDecode('"${value.replaceAll('"', r'\"')}"') as String;
    } catch (_) {}
    return value;
  }
}

class _CaptureEnvelope {
  const _CaptureEnvelope({
    required this.html,
    required this.runtimeMedia,
    this.pageUrl,
    this.canonicalUrl,
    this.hasVideoHint = false,
  });

  final String html;
  final String? pageUrl;
  final String? canonicalUrl;
  final List<_RuntimeMedia> runtimeMedia;
  final bool hasVideoHint;
}

class _RuntimeMedia {
  const _RuntimeMedia({
    required this.kind,
    required this.url,
    this.width,
    this.height,
  });

  final String kind;
  final String url;
  final int? width;
  final int? height;
}
