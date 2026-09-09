import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/services/universal_platform_detector.dart';

void main() {
  test('detects supported social platforms', () {
    final cases = <String, SocialPlatform>{
      'https://www.threads.com/@user/post/abc': SocialPlatform.threads,
      'https://vm.tiktok.com/ZMh/': SocialPlatform.tiktok,
      'https://www.instagram.com/reel/abc/': SocialPlatform.instagram,
      'https://x.com/user/status/123': SocialPlatform.x,
      'https://pin.it/abc': SocialPlatform.pinterest,
      'https://fb.watch/abc': SocialPlatform.facebook,
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

  test('marks Instagram and Facebook for Smart Capture fallback', () {
    expect(UniversalPlatformDetector.detect('https://www.instagram.com/reel/abc/').usesCaptureFallback, isTrue);
    expect(UniversalPlatformDetector.detect('https://www.facebook.com/watch/?v=1').usesCaptureFallback, isTrue);
    expect(UniversalPlatformDetector.detect('https://vm.tiktok.com/ZMh/').usesCaptureFallback, isFalse);
    expect(UniversalPlatformDetector.detect('https://www.threads.com/@user/post/abc').isThreads, isTrue);
  });
}
