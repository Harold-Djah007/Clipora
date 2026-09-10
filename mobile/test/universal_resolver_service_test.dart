import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/models/media_models.dart';
import 'package:threadvault/services/universal_resolver_service.dart';

void main() {
  test('reports no backend when the APK and settings are blank', () {
    final service = UniversalResolverService();

    expect(service.hasConfiguredBackend, isFalse);
    expect(service.baseUrls, isEmpty);
  });

  test('converts backend universal resolver JSON into mobile post model', () {
    final post = UniversalResolverService.postFromJson(
      {
        'post_id': 'abc123',
        'author': 'creator name',
        'platform': 'tiktok',
        'source_url': 'https://www.tiktok.com/@creator/video/123',
        'caption': 'caption text',
        'media': [
          {
            'media_type': 'video',
            'url': 'https://cdn.example.com/video.mp4',
            'width': 1080,
            'height': 1920,
          }
        ],
      },
      fallbackUrl: 'https://fallback.example/post',
    );

    expect(post.postId, 'abc123');
    expect(post.author, 'creator_name');
    expect(post.caption, 'caption text');
    expect(post.media, hasLength(1));
    expect(post.media.first.kind, MediaKind.video);
    expect(post.media.first.url, endsWith('video.mp4'));
  });

  test('prefixes backend file fallback paths with the resolver base URL', () {
    final post = UniversalResolverService.postFromJson(
      {
        'post_id': 'yt1',
        'author': 'creator',
        'media': [
          {'media_type': 'video', 'url': '/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'},
        ],
      },
      fallbackUrl: 'https://youtu.be/abc',
      baseUrl: 'http://192.168.1.10:8010',
    );

    expect(post.media.single.url, 'http://192.168.1.10:8010/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  });

  test('preserves GIF media type from the resolver', () {
    final post = UniversalResolverService.postFromJson(
      {
        'post_id': 'gif1',
        'author': 'creator',
        'media': [
          {'media_type': 'image', 'mime_type': 'image/gif', 'url': 'https://cdn.example/animation.gif'},
        ],
      },
      fallbackUrl: 'https://pin.it/example',
    );

    expect(post.media.single.kind, MediaKind.image);
    expect(post.media.single.mimeType, 'image/gif');
  });

  test('rejects universal resolver JSON without media', () {
    expect(
      () => UniversalResolverService.postFromJson({'media': []}, fallbackUrl: 'https://example.com'),
      throwsA(isA<FormatException>()),
    );
  });
}
