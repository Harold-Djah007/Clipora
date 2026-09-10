import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/services/universal_platform_detector.dart';

void main() {
  test('detects supported social platforms', () {
    final cases = <String, SocialPlatform>{
      'https://www.threads.com/@user/post/abc': SocialPlatform.threads,
      'https://www.threads.com/share/short123': SocialPlatform.threads,
      'https://vm.tiktok.com/ZMh/': SocialPlatform.tiktok,
      'https://www.instagram.com/reel/abc/': SocialPlatform.instagram,
      'https://x.com/user/status/123': SocialPlatform.x,
      'https://pin.it/abc': SocialPlatform.pinterest,
      'https://fb.me/abc': SocialPlatform.facebook,
      'https://story.snapchat.com/p/example': SocialPlatform.snapchat,
      'https://youtu.be/abc': SocialPlatform.youtube,
    };

    for (final entry in cases.entries) {
      expect(UniversalPlatformDetector.detect(entry.key).platform, entry.value, reason: entry.key);
    }
  });

  test('marks unknown or invalid links as unsupported', () {
    expect(UniversalPlatformDetector.detect('not a url').isSupported, isFalse);
    expect(UniversalPlatformDetector.detect('https://example.com/video').platform, SocialPlatform.unknown);
  });

  test('marks Instagram and Facebook as supported resolver platforms', () {
    expect(UniversalPlatformDetector.detect('https://www.instagram.com/reel/abc/').isSupported, isTrue);
    expect(UniversalPlatformDetector.detect('https://www.facebook.com/watch/?v=1').isSupported, isTrue);
    expect(UniversalPlatformDetector.detect('https://vm.tiktok.com/ZMh/').isSupported, isTrue);
    expect(UniversalPlatformDetector.detect('https://www.threads.com/@user/post/abc').isThreads, isTrue);
  });

  test('unwraps Facebook l.php wrappers and drops duplicate post URLs', () {
    final urls = UniversalPlatformDetector.extractShareUrls(
      'Watch https://www.facebook.com/watch/?v=1081678357921979 '
      'https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.facebook.com%2Fwatch%2F%3Fv%3D1081678357921979&h=AT',
    );
    expect(urls, ['https://www.facebook.com/watch/?v=1081678357921979']);
  });
}
