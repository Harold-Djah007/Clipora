import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/services/threads_parser.dart';
import 'package:threadvault/models/media_models.dart';

void main() {
  final parser = ThreadsParser();

  test('parses progressive Threads video', () {
    const source = r'''
      <html><script type="application/json">
      {"video_versions":[{"type":101,"url":"https:\/\/example.cdninstagram.com\/clip.mp4?a=1\u0026b=2"}]}
      </script></html>
    ''';
    final post = parser.parse(source, 'https://www.threads.com/@alice/post/ABC');
    expect(post.author, 'alice');
    expect(post.postId, 'ABC');
    expect(post.media.single.kind, MediaKind.video);
    expect(post.media.single.url, 'https://example.cdninstagram.com/clip.mp4?a=1&b=2');
  });

  test('parses runtime resolver envelope', () {
    const source = r'''{"html":"<html></html>","runtimeUrls":["https://scontent.cdninstagram.com/v/t1/file.jpg?x=1"],"pageUrl":"https://www.threads.com/@bob/post/XYZ"}''';
    final post = parser.parse(source, 'https://www.threads.com/share/short123');
    expect(post.author, 'bob');
    expect(post.postId, 'XYZ');
    expect(post.media.single.kind, MediaKind.image);
  });

  test('rejects source without media', () {
    expect(
      () => parser.parse('<html>none</html>', 'https://www.threads.com/@a/post/b'),
      throwsA(isA<FormatException>()),
    );
  });
}
