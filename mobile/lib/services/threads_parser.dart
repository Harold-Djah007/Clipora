import 'dart:convert';
import 'package:collection/collection.dart';
import '../models/media_models.dart';

class ThreadsParser {
  static final RegExp _postId = RegExp(r'/post/([^?/#]+)');
  static final RegExp _author = RegExp(r'threads\.(?:com|net)/@([^/]+)');

  ResolvedPost parse(String source, String postUrl) {
    final envelope = _decodeEnvelope(source);
    final normalized = _decodeHtml(envelope.html);
    final isShareLink = _isSharePostUrl(postUrl);
    final captureMode = envelope.captureMode ?? '';

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
    final videoHint = envelope.hasVideoHint || _hasVideoHint(normalized);

    // Runtime DOM media is the safest signal because it comes from the actual
    // post card that loaded in the WebView. But do not stop there: Threads
    // often exposes a poster image before the MP4/video_versions arrive. The
    // previous build completed too early and saved that poster as a bad image.
    // Always scan the scoped HTML for video candidates before accepting images.
    _extractRuntimeMedia(envelope.runtimeMedia, media);
    _extractProgressiveVideos(normalized, media);

    // Only use broad direct-MP4 scanning as a fallback. When video_versions has
    // already selected the best variant, another broad scan would re-add the low
    // and high variants as separate downloads. That was the 0.7.9 test failure.
    if (!media.any((e) => e.kind == MediaKind.video)) {
      _extractDirectVideos(normalized, media);
    }

    // Safer rule: when a video exists anywhere in the scoped snapshot, do not
    // add generic image/poster URLs. This keeps video posts as MP4-only. If the
    // snapshot only says "video" but no concrete MP4 is extractable yet, fail
    // instead of saving the low-quality poster image.
    if (!media.any((e) => e.kind == MediaKind.video)) {
      if (videoHint) {
        throw const FormatException(
          'This looks like a video post, but Threads only exposed the poster image so far. Open Private Capture, play the video once, then tap Capture again.',
        );
      }
      _extractImages(normalized, media);
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

    var values = unique.values.toList();
    final videos = values.where((item) => item.kind == MediaKind.video).toList();
    if (videos.isNotEmpty) {
      // For video posts, never save poster frames / preview images alongside the MP4.
      // This is safer for Threads private-capture pages, which often expose both.
      values = videos;
    }
    if (values.isNotEmpty &&
        videos.isEmpty &&
        isShareLink &&
        captureMode != 'privatePhoto') {
      throw const FormatException(
        'Clipora only saw a poster/photo from this Threads share link. If it is a video, open Private Capture, play it once, then tap Video. If it is truly a photo post, tap Photos.',
      );
    }
    if (values.isEmpty) {
      final pageUrl = envelope.pageUrl ?? '';
      if (pageUrl.toLowerCase().contains('error=invalid_post')) {
        throw const FormatException(
          'Threads returned invalid_post before real media was available. Open Private Access, confirm the post plays there, then retry the share link.',
        );
      }
      throw const FormatException(
        'No real Threads post media was found. Clipora ignored page artwork, static scripts, icons, PNGs and audio assets.',
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

  bool _hasVideoHint(String source) {
    final lower = source.toLowerCase();
    return lower.contains('video_versions') ||
        lower.contains('playable_url') ||
        lower.contains('video_url') ||
        lower.contains('.mp4') ||
        lower.contains('mime_type=video');
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
      final candidates = <ResolvedMedia>[];

      final objects = RegExp(r'\{[^{}]*"url"\s*:\s*"([^"]+)"[^{}]*\}', dotAll: true).allMatches(body);
      for (final object in objects) {
        final rawObject = object.group(0) ?? '';
        final url = _unescape(object.group(1) ?? '');
        if (!_looksLikeVideo(url) || !_isAllowedMediaUrl(url)) continue;
        candidates.add(ResolvedMedia(
          kind: MediaKind.video,
          url: url,
          width: _jsonInt(rawObject, 'width'),
          height: _jsonInt(rawObject, 'height'),
          mimeType: 'video/mp4',
        ));
      }

      if (candidates.isEmpty) {
        for (final candidate in RegExp(r'"url"\s*:\s*"([^"]+)"').allMatches(body)) {
          final url = _unescape(candidate.group(1) ?? '');
          if (_looksLikeVideo(url) && _isAllowedMediaUrl(url)) {
            candidates.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
          }
        }
      }

      candidates.sort((a, b) => _mediaScore(b).compareTo(_mediaScore(a)));
      if (candidates.isNotEmpty) out.add(candidates.first);
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
          hasVideoHint: decoded['hasVideo'] == true,
          captureMode: decoded['captureMode'] is String ? decoded['captureMode'] as String : null,
        );
      }
    } catch (_) {}
    return _ResolverEnvelope(html: decodedInput, runtimeMedia: const []);
  }

  bool _isSharePostUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return false;
    final host = parsed.host.toLowerCase();
    return (host == 'threads.com' || host.endsWith('.threads.com') || host == 'threads.net' || host.endsWith('.threads.net')) &&
        parsed.path.toLowerCase().startsWith('/share/');
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value');
  }

  int? _jsonInt(String source, String key) {
    final match = RegExp('"$key"\\s*:\\s*(\\d+)').firstMatch(source);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  int _mediaScore(ResolvedMedia item) {
    final width = item.width ?? 0;
    final height = item.height ?? 0;
    final area = width * height;
    // Give unknown MP4s a usable score so they still beat images, while
    // higher-resolution video_versions win when Threads provides dimensions.
    return area > 0 ? area : (item.kind == MediaKind.video ? 1 : 0);
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
    this.hasVideoHint = false,
    this.captureMode,
  });

  final String html;
  final String? pageUrl;
  final String? canonicalUrl;
  final List<_RuntimeMedia> runtimeMedia;
  final bool hasVideoHint;
  final String? captureMode;
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
