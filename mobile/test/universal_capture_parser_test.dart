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

  test('field mode keeps multiple runtime videos from one carousel', () {
    final platform = UniversalPlatformDetector.detect('https://www.tiktok.com/@creator/video/123');
    final source = jsonEncode({
      'html': '<html><video></video></html>',
      'pageUrl': 'https://www.tiktok.com/@creator/video/123',
      'hasVideo': true,
      'runtimeMedia': [
        {
          'kind': 'video',
          'url': 'https://v16-webapp-prime.tiktok.com/video/tos/useast2a/clip-a/?mime=video_mp4',
          'width': 720,
          'height': 1280,
        },
        {
          'kind': 'video',
          'url': 'https://v16-webapp-prime.tiktok.com/video/tos/useast2a/clip-b/?mime=video_mp4',
          'width': 1080,
          'height': 1920,
        },
      ],
    });

    final post = UniversalCaptureParser().parse(source, 'https://www.tiktok.com/@creator/video/123', platform);

    expect(post.media, hasLength(2));
    expect(post.media.map((item) => item.url), containsAll(['https://v16-webapp-prime.tiktok.com/video/tos/useast2a/clip-a/?mime=video_mp4', 'https://v16-webapp-prime.tiktok.com/video/tos/useast2a/clip-b/?mime=video_mp4']));
  });

  test('field mode caps captured carousel media at twenty items', () {
    final platform = UniversalPlatformDetector.detect('https://x.com/creator/status/123');
    final source = jsonEncode({
      'html': '<html><video></video></html>',
      'pageUrl': 'https://x.com/creator/status/123',
      'hasVideo': true,
      'runtimeMedia': [
        for (var i = 0; i < 25; i++)
          {
            'kind': 'video',
            'url': 'https://video.twimg.com/ext_tw_video/$i/pu/vid/720x1280/clip-$i.mp4',
            'width': 720,
            'height': 1280,
          }
      ],
    });

    final post = UniversalCaptureParser().parse(source, 'https://x.com/creator/status/123', platform);

    expect(post.media, hasLength(20));
    expect(post.media.first.url, contains('clip-0.mp4'));
    expect(post.media.last.url, contains('clip-19.mp4'));
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
