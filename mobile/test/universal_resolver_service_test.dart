import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/models/media_models.dart';
import 'package:threadvault/services/universal_resolver_service.dart';

void main() {
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

  test('rejects universal resolver JSON without media', () {
    expect(
      () => UniversalResolverService.postFromJson({'media': []}, fallbackUrl: 'https://example.com'),
      throwsA(isA<FormatException>()),
    );
  });
}
