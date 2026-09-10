import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/services/download_manager.dart';

void main() {
  const threadsPost = 'https://www.threads.com/@alice/post/ABC';

  test('Threads saves allow Instagram CDN photos and videos', () {
    expect(
      isSafePostMediaUrl('https://scontent.cdninstagram.com/v/t1/real.mp4', threadsPost),
      isTrue,
    );
    expect(
      isSafePostMediaUrl('https://scontent.cdninstagram.com/v/t51/a.jpg', threadsPost),
      isTrue,
    );
  });

  test('Threads saves allow resolver /api/files tunnels', () {
    expect(
      isSafePostMediaUrl('http://127.0.0.1:8010/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', threadsPost),
      isTrue,
    );
    expect(
      isSafePostMediaUrl('https://resolver.example/api/files/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', threadsPost),
      isTrue,
    );
  });

  test('Threads saves still skip page artwork and audio', () {
    expect(
      isSafePostMediaUrl('https://static.cdninstagram.com/rsrc.php/v4/ui.mp4', threadsPost),
      isFalse,
    );
    expect(
      isSafePostMediaUrl('https://scontent.cdninstagram.com/v/t51/audio.m4a', threadsPost),
      isFalse,
    );
  });
}
