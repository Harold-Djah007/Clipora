import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/models/media_models.dart';
import 'package:threadvault/services/universal_capture_parser.dart';
import 'package:threadvault/services/universal_platform_detector.dart';

void main() {
  test('parses non-Threads capture runtime video media', () {
    final platform = UniversalPlatformDetector.detect('https://www.instagram.com/reel/Dc-Of-yuCCq/');
    final source = jsonEncode({
      'html': '<html><meta property="og:description" content="caption"></html>',
      'pageUrl': 'https://www.instagram.com/reel/Dc-Of-yuCCq/',
      'canonicalUrl': 'https://www.instagram.com/reel/Dc-Of-yuCCq/',
      'hasVideo': true,
      'runtimeMedia': [
        {
          'kind': 'video',
          'url': 'https://scontent.cdninstagram.com/o1/v/t16/f2/m86/video.mp4?token=abc',
          'width': 720,
          'height': 1280,
        },
        {
          'kind': 'image',
          'url': 'https://scontent.cdninstagram.com/v/t51/poster.jpg',
          'width': 720,
          'height': 1280,
        },
      ],
    });

    final post = UniversalCaptureParser().parse(source, 'https://www.instagram.com/reel/Dc-Of-yuCCq/', platform);

    expect(post.postId, 'Dc-Of-yuCCq');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.video);
    expect(post.media.single.url, contains('video.mp4'));
  });

  test('does not save a poster when capture says the page is a video', () {
    final platform = UniversalPlatformDetector.detect('https://www.instagram.com/reel/Dc-Of-yuCCq/');
    final source = jsonEncode({
      'html': '<html><video></video></html>',
      'pageUrl': 'https://www.instagram.com/reel/Dc-Of-yuCCq/',
      'hasVideo': true,
      'runtimeMedia': [
        {
          'kind': 'image',
          'url': 'https://scontent.cdninstagram.com/v/t51/poster.jpg',
          'width': 720,
          'height': 1280,
        },
      ],
    });

    expect(
      () => UniversalCaptureParser().parse(source, 'https://www.instagram.com/reel/Dc-Of-yuCCq/', platform),
      throwsA(isA<FormatException>()),
    );
  });
}
