import 'dart:convert';
import 'package:collection/collection.dart';
import '../models/media_models.dart';

class ThreadsParser {
  static final RegExp _postId = RegExp(r'/post/([^?/#]+)');
  static final RegExp _author = RegExp(r'threads\.com/@([^/]+)');

  ResolvedPost parse(String source, String postUrl) {
    final normalized = _decodeHtml(source);
    final postId = _postId.firstMatch(postUrl)?.group(1) ?? 'thread';
    final author = _author.firstMatch(postUrl)?.group(1) ?? 'threads';
    final caption = _extractCaption(normalized);
    final media = <ResolvedMedia>[];

    // Progressive video URLs are the preferred output because they generally
    // contain audio and video together and are easier to save than DASH sets.
    final progressive = RegExp(
      r'"video_versions"\s*:\s*\[(.*?)\]',
      dotAll: true,
    ).allMatches(normalized);
    for (final block in progressive) {
      final body = block.group(1) ?? '';
      final m = RegExp(r'"url"\s*:\s*"(https?:[^\"]+\.mp4[^\"]*)"').firstMatch(body);
      if (m != null) {
        final url = _unescape(m.group(1)!);
        if (url.isNotEmpty) {
          media.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
        }
      }
    }

    // Fallback for MP4 URLs in DASH BaseURL entries.
    if (!media.any((e) => e.kind == MediaKind.video)) {
      for (final m in RegExp(r'https?:\\?/\\?/[^"< ]+?\.mp4[^"< ]*').allMatches(normalized)) {
        final url = _unescape(m.group(0)!);
        if (url.startsWith('http')) {
          media.add(ResolvedMedia(kind: MediaKind.video, url: url, mimeType: 'video/mp4'));
        }
      }
    }

    // Threads payloads use several image-url field names. Ignore avatars and
    // static assets by preferring media payload fields and CDN image URLs.
    final imagePatterns = [
      RegExp(r'"image_versions2"\s*:\s*\{.*?"candidates"\s*:\s*\[(.*?)\]', dotAll: true),
      RegExp(r'"display_url"\s*:\s*"(https?:[^\"]+)"'),
      RegExp(r'"image_url"\s*:\s*"(https?:[^\"]+)"'),
    ];
    for (final pattern in imagePatterns) {
      for (final block in pattern.allMatches(normalized)) {
        final text = block.groupCount > 0 ? (block.group(1) ?? '') : block.group(0)!;
        final candidates = RegExp(r'"url"\s*:\s*"(https?:[^\"]+)"').allMatches(text);
        if (candidates.isEmpty && block.groupCount > 0 && (block.group(1) ?? '').startsWith('http')) {
          media.add(ResolvedMedia(kind: MediaKind.image, url: _unescape(block.group(1)!)));
        } else {
          final c = candidates.firstOrNull;
          if (c != null) {
            final url = _unescape(c.group(1)!);
            if (_looksLikePostImage(url)) {
              media.add(ResolvedMedia(kind: MediaKind.image, url: url, mimeType: 'image/jpeg'));
            }
          }
        }
      }
    }

    final unique = <String, ResolvedMedia>{};
    for (final item in media) {
      unique[item.url] = item;
    }
    final values = unique.values.toList();
    if (values.isEmpty) {
      throw const FormatException('No downloadable media was found in this post.');
    }
    return ResolvedPost(
      sourceUrl: postUrl,
      postId: postId,
      author: author,
      caption: caption,
      media: values,
    );
  }

  String? _extractCaption(String source) {
    final candidates = [
      RegExp(r'"caption"\s*:\s*\{[^}]*"text"\s*:\s*"(.*?)"', dotAll: true),
      RegExp(r'<meta[^>]+property="og:description"[^>]+content="([^"]+)"'),
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

  bool _looksLikePostImage(String url) {
    final lower = url.toLowerCase();
    return (lower.contains('cdninstagram') || lower.contains('fbcdn')) &&
        (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.webp'));
  }

  String _decodeHtml(String input) => input
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  String _unescape(String input) {
    var value = input
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u00253D', '%3D')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003F', '?')
        .replaceAll(r'\u0025', '%')
        .replaceAll('&amp;', '&');
    try {
      value = jsonDecode('"${value.replaceAll('"', r'\"')}"') as String;
    } catch (_) {}
    return value;
  }
}
