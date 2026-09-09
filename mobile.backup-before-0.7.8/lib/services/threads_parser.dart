import 'dart:convert';
import 'package:collection/collection.dart';
import '../models/media_models.dart';

class ThreadsParser {
  static final RegExp _postId = RegExp(r'/post/([^?/#]+)');
  static final RegExp _author = RegExp(r'threads\.(?:com|net)/@([^/]+)');

  ResolvedPost parse(String source, String postUrl) {
    final envelope = _decodeEnvelope(source);
    final normalized = _decodeHtml(envelope.html);

    final identityCandidates = <String>[
      envelope.canonicalUrl ?? '',
      envelope.pageUrl ?? '',
      postUrl,
      RegExp(r'https://(?:www\.)?threads\.(?:com|net)/@[^/\s]+/post/[^?/#\s]+')
              .firstMatch(normalized)
              ?.group(0) ??
          '',
    ];
    final identityUrl = identityCandidates.firstWhere(
      (u) => u.contains('/post/'),
      orElse: () => postUrl,
    );
    final postId = _postId.firstMatch(identityUrl)?.group(1) ?? 'thread';
    final author = _author.firstMatch(identityUrl)?.group(1) ?? 'threads';
    final caption = _extractCaption(normalized);
    final media = <ResolvedMedia>[];

    // Runtime DOM media is the safest signal because it comes from the actual
    // post card that loaded in the WebView. When it exists, never mix it with
    // full-page HTML assets or recommendations.
    _extractRuntimeMedia(envelope.runtimeMedia, media);

    if (media.isEmpty) {
      _extractProgressiveVideos(normalized, media);
      if (!media.any((e) => e.kind == MediaKind.video)) {
        _extractDirectVideos(normalized, media);
      }
      // Safer rule: when an HTML fallback already found a video, do not add
      // generic image/poster URLs. This prevents saving unrelated WebP/PNG
      // artwork for a video post. Runtime-media mode above still supports true
      // mixed carousels because it is scoped to the rendered post card.
      if (!media.any((e) => e.kind == MediaKind.video)) {
        _extractImages(normalized, media);
      }
    }

    final unique = <String, ResolvedMedia>{};
    for (final item in media) {
      final cleaned = _unescape(item.url);
      if (!_isAllowedMediaUrl(cleaned)) continue;
      unique[cleaned] = ResolvedMedia(
        kind: item.kind,
        url: cleaned,
        width: item.width,
        height: item.height,
        mimeType: item.mimeType,
      );
    }

    final values = unique.values.toList();
    if (values.isEmpty) {
      final pageUrl = envelope.pageUrl ?? '';
      if (pageUrl.toLowerCase().contains('error=invalid_post')) {
        throw const FormatException(
          'Threads returned invalid_post before real media was available. Open Private Access, confirm the post plays there, then retry the share link.',
        );
      }
      throw const FormatException(
        'No real Threads post media was found. ThreadVault ignored page artwork, static scripts, icons, PNGs and audio assets.',
      );
    }
    return ResolvedPost(
      sourceUrl: postUrl,
      postId: postId,
      author: author,
      caption: caption,
      media: values,
    );
  }

  void _extractRuntimeMedia(List<_RuntimeMedia> runtime, List<ResolvedMedia> out) {
    for (final item in runtime) {
      final url = _unescape(item.url);
      if (!_isAllowedMediaUrl(url)) continue;
      if (item.kind == 'video' && _looksLikeVideo(url)) {
        out.add(ResolvedMedia(
          kind: MediaKind.video,
          url: url,
          width: item.width,
          height: item.height,
          mimeType: 'video/mp4',
        ));
      } else if (item.kind == 'image' && _looksLikePostImage(url)) {
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

  void _extractProgressiveVideos(String source, List<ResolvedMedia> out) {
    final blocks = RegExp(r'"video_versions"\s*:\s*\[(.*?)\]', dotAll: true).allMatches(source);
    for (final block in blocks) {
      final body = block.group(1) ?? '';
      final candidates = RegExp(r'"url"\s*:\s*"([^"]+)"').allMatches(body).toList();
      final first = candidates.firstWhereOrNull((candidate) {
        final url = _unescape(candidate.group(1) ?? '');
        return _looksLikeVideo(url) && _isAllowedMediaUrl(url);
      });
      if (first != null) {
        final url = _unescape(first.group(1) ?? '');
        out.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
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
        if (_looksLikeVideo(url) && _isAllowedMediaUrl(url)) {
          out.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
        }
      }
    }
  }

  void _extractImages(String source, List<ResolvedMedia> out) {
    final candidateBlocks = RegExp(
      r'"image_versions2"\s*:\s*\{.*?"candidates"\s*:\s*\[(.*?)\]',
      dotAll: true,
    ).allMatches(source);
    for (final block in candidateBlocks) {
      final urls = RegExp(r'"url"\s*:\s*"([^"]+)"').allMatches(block.group(1) ?? '');
      final first = urls.firstWhereOrNull((m) {
        final url = _unescape(m.group(1) ?? '');
        return _looksLikePostImage(url) && _isAllowedMediaUrl(url);
      });
      if (first != null) {
        final url = _unescape(first.group(1) ?? '');
        out.add(ResolvedMedia(kind: MediaKind.image, url: url, mimeType: _imageMime(url)));
      }
    }

    if (!out.any((e) => e.kind == MediaKind.image)) {
      final directPatterns = [
        RegExp(r'"(?:display_url|image_url|thumbnail_url)"\s*:\s*"([^"]+)"', caseSensitive: false),
        RegExp(r'''https?://[^"'<>\s]+?\.(?:jpe?g|png|webp)(?:\?[^"'<>\s]*)?''', caseSensitive: false),
      ];
      for (final pattern in directPatterns) {
        for (final match in pattern.allMatches(source)) {
          final raw = match.groupCount > 0 ? match.group(1) : match.group(0);
          final url = _unescape(raw ?? '');
          if (_looksLikePostImage(url) && _isAllowedMediaUrl(url)) {
            out.add(ResolvedMedia(kind: MediaKind.image, url: url, mimeType: _imageMime(url)));
          }
        }
      }
    }
  }

  String? _extractCaption(String source) {
    final candidates = [
      RegExp(r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"(.*?)"', dotAll: true),
      RegExp(r'"text_post_app_info".*?"text"\s*:\s*"(.*?)"', dotAll: true),
      RegExp(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"', caseSensitive: false),
    ];
    for (final p in candidates) {
      final match = p.firstMatch(source);
      if (match != null) {
        final text = _unescape(match.group(1) ?? '').trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  _ResolverEnvelope _decodeEnvelope(String input) {
    final decodedInput = _decodeHtml(input);
    try {
      final decoded = jsonDecode(decodedInput);
      if (decoded is Map) {
        final runtime = <_RuntimeMedia>[];
        final rawRuntime = decoded['runtimeMedia'];
        if (rawRuntime is List) {
          for (final item in rawRuntime) {
            if (item is! Map) continue;
            final kind = item['kind'];
            final url = item['url'];
            if (kind is! String || url is! String) continue;
            runtime.add(_RuntimeMedia(
              kind: kind,
              url: url,
              width: _asInt(item['width']),
              height: _asInt(item['height']),
            ));
          }
        }
        return _ResolverEnvelope(
          html: decoded['html'] is String ? decoded['html'] as String : decodedInput,
          pageUrl: decoded['pageUrl'] is String ? decoded['pageUrl'] as String : null,
          canonicalUrl: decoded['canonicalUrl'] is String ? decoded['canonicalUrl'] as String : null,
          runtimeMedia: runtime,
        );
      }
    } catch (_) {}
    return _ResolverEnvelope(html: decodedInput, runtimeMedia: const []);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }

  bool _looksLikeVideo(String url) {
    final lower = url.toLowerCase();
    return _isHttp(url) &&
        !_looksLikeAudio(url) &&
        (lower.contains('.mp4') || lower.contains('mime_type=video'));
  }

  bool _looksLikeAudio(String url) {
    final lower = url.toLowerCase();
    return lower.contains('mime_type=audio') ||
        lower.contains('/audio/') ||
        lower.contains('.m4a') ||
        lower.contains('.mp3') ||
        lower.contains('.aac');
  }

  bool _looksLikePostImage(String url) {
    final lower = url.toLowerCase();
    final isCdn = lower.contains('cdninstagram') || lower.contains('fbcdn') || lower.contains('instagram');
    final isImage = lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp');
    final blocked = lower.contains('profile_pic') || lower.contains('sprite') || lower.contains('favicon');
    return _isHttp(url) && isCdn && isImage && !blocked;
  }

  bool _isAllowedMediaUrl(String url) {
    if (!_isHttp(url) || url.startsWith('blob:')) return false;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;
    final host = parsed.host.toLowerCase();
    final lower = url.toLowerCase();
    if (host == 'static.cdninstagram.com') return false;
    if (lower.contains('/rsrc.php/') || lower.contains('/static/')) return false;
    if (_looksLikeAudio(url)) return false;
    final goodHost = host.contains('cdninstagram.com') || host.contains('fbcdn.net');
    if (!goodHost) return false;
    return _looksLikeVideo(url) || _looksLikePostImage(url);
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

class _ResolverEnvelope {
  const _ResolverEnvelope({
    required this.html,
    required this.runtimeMedia,
    this.pageUrl,
    this.canonicalUrl,
  });

  final String html;
  final String? pageUrl;
  final String? canonicalUrl;
  final List<_RuntimeMedia> runtimeMedia;
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
