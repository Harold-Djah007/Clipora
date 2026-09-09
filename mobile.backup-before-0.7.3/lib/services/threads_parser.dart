import 'dart:convert';
import 'package:collection/collection.dart';
import '../models/media_models.dart';

class ThreadsParser {
  static final RegExp _postId = RegExp(r'/post/([^?/#]+)');
  static final RegExp _author = RegExp(r'threads\.(?:com|net)/@([^/]+)');

  ResolvedPost parse(String source, String postUrl) {
    final normalized = _normalizeSource(source);
    final canonicalMatch = RegExp(r'https://(?:www\.)?threads\.(?:com|net)/@[^/\s]+/post/[^?/#\s]+')
        .firstMatch(normalized);
    final identityUrl = postUrl.contains('/post/') ? postUrl : (canonicalMatch?.group(0) ?? postUrl);
    final postId = _postId.firstMatch(identityUrl)?.group(1) ?? 'thread';
    final author = _author.firstMatch(identityUrl)?.group(1) ?? 'threads';
    final caption = _extractCaption(normalized);
    final media = <ResolvedMedia>[];

    _extractProgressiveVideos(normalized, media);
    if (!media.any((e) => e.kind == MediaKind.video)) {
      _extractDirectVideos(normalized, media);
    }
    _extractImages(normalized, media);

    final unique = <String, ResolvedMedia>{};
    for (final item in media) {
      final cleaned = _unescape(item.url);
      if (!_isHttp(cleaned) || cleaned.startsWith('blob:')) continue;
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
      throw const FormatException(
        'No downloadable media was found. Open the post in Private Access first if it needs login, then retry.',
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

  void _extractProgressiveVideos(String source, List<ResolvedMedia> out) {
    final blocks = RegExp(r'"video_versions"\s*:\s*\[(.*?)\]', dotAll: true).allMatches(source);
    for (final block in blocks) {
      final body = block.group(1) ?? '';
      final candidates = RegExp(r'"url"\s*:\s*"([^"]+)"').allMatches(body);
      for (final candidate in candidates) {
        final url = _unescape(candidate.group(1) ?? '');
        if (_looksLikeVideo(url)) {
          out.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
          break;
        }
      }
    }
  }

  void _extractDirectVideos(String source, List<ResolvedMedia> out) {
    final patterns = [
      RegExp(r'"(?:video_url|playable_url|src)"\s*:\s*"([^"]+\.mp4[^"]*)"', caseSensitive: false),
      RegExp(r'''https?:\\?/\\?/[^"'<> ]+?\.mp4[^"'<> ]*''', caseSensitive: false),
      RegExp(r'''https?://[^"'<> ]+?\.mp4[^"'<> ]*''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final raw = match.groupCount > 0 ? match.group(1) : match.group(0);
        final url = _unescape(raw ?? '');
        if (_looksLikeVideo(url)) {
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
      final first = urls.firstOrNull;
      if (first != null) {
        final url = _unescape(first.group(1) ?? '');
        if (_looksLikePostImage(url)) {
          out.add(ResolvedMedia(kind: MediaKind.image, url: url, mimeType: _imageMime(url)));
        }
      }
    }

    // Prefer structured post image fields. Only fall back to generic CDN
    // images when Threads has changed the payload shape; this avoids saving
    // avatars and UI artwork from the page.
    if (!out.any((e) => e.kind == MediaKind.image)) {
      final directPatterns = [
        RegExp(r'"(?:display_url|image_url|thumbnail_url)"\s*:\s*"([^"]+)"', caseSensitive: false),
        RegExp(r'''https?://[^"'<> ]+?\.(?:jpe?g|png|webp)(?:\?[^"'<> ]*)?''', caseSensitive: false),
      ];
      for (final pattern in directPatterns) {
        for (final match in pattern.allMatches(source)) {
          final raw = match.groupCount > 0 ? match.group(1) : match.group(0);
          final url = _unescape(raw ?? '');
          if (_looksLikePostImage(url)) {
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

  String _normalizeSource(String input) {
    var value = _decodeHtml(input);
    // The browser resolver can return a JSON envelope containing HTML plus
    // runtime media/resource URLs. Appending all values gives the parser one
    // resilient text surface without depending on a private API schema.
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final pieces = <String>[];
        for (final entry in decoded.entries) {
          final v = entry.value;
          if (v is String) pieces.add(v);
          if (v is List) pieces.addAll(v.whereType<String>());
        }
        if (pieces.isNotEmpty) value = pieces.join('\n');
      }
    } catch (_) {}
    return _decodeHtml(value);
  }

  bool _looksLikeVideo(String url) => _isHttp(url) && url.toLowerCase().contains('.mp4');

  bool _looksLikePostImage(String url) {
    final lower = url.toLowerCase();
    final isCdn = lower.contains('cdninstagram') || lower.contains('fbcdn') || lower.contains('instagram');
    final isImage = lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp');
    return _isHttp(url) && isCdn && isImage && !lower.contains('profile_pic');
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
