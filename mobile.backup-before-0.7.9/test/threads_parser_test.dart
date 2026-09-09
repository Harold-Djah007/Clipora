import 'dart:convert';
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

  test('prefers scoped runtime media and ignores static page artwork', () {
    const source = r'''{
      "html":"<html><script>{\"video_versions\":[{\"url\":\"https://static.cdninstagram.com/unrelated.mp4\"}]}</script></html>",
      "runtimeMedia":[
        {"kind":"video","url":"https://scontent.cdninstagram.com/v/t1/real.mp4?x=1","width":1080,"height":1920},
        {"kind":"image","url":"https://static.cdninstagram.com/rsrc.php/v4/icon.png","width":512,"height":512}
      ],
      "pageUrl":"https://www.threads.com/?error=invalid_post",
      "canonicalUrl":"https://www.threads.com/@bob/post/XYZ"
    }''';
    final post = parser.parse(source, 'https://www.threads.com/share/short123');
    expect(post.author, 'bob');
    expect(post.postId, 'XYZ');
    expect(post.media.length, 1);
    expect(post.media.single.kind, MediaKind.video);
    expect(post.media.single.url, contains('/real.mp4'));
  });

  test('does not accept static cdn mp4 as a post video', () {
    const source = r'''{"video_versions":[{"url":"https://static.cdninstagram.com/rsrc.php/v4/ui.mp4"}]}''';
    expect(
      () => parser.parse(source, 'https://www.threads.com/@a/post/b'),
      throwsA(isA<FormatException>()),
    );
  });

  test('does not save generic images when a real video was already found from html', () {
    const source = r'''
      <html><script>
      {"video_versions":[{"url":"https://scontent.cdninstagram.com/v/t1/real.mp4?x=1"}],
       "image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/v/t51/poster.webp?x=2"}]}}
      </script></html>
    ''';
    final post = parser.parse(source, 'https://www.threads.com/@alice/post/ABC');
    expect(post.media.length, 1);
    expect(post.media.single.kind, MediaKind.video);
  });

  test('rejects invalid_post error page even when it has static media assets', () {
    const source = r'''{
      "html":"<html><script src='https://static.cdninstagram.com/rsrc.php/v4/ui.mp4'></script><img src='https://static.cdninstagram.com/rsrc.php/v4/icon.png'></html>",
      "runtimeMedia":[],
      "pageUrl":"https://www.threads.com/?error=invalid_post",
      "canonicalUrl":"https://www.threads.com/?error=invalid_post"
    }''';
    expect(
      () => parser.parse(source, 'https://www.threads.com/share/short123'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects source without media', () {
    expect(
      () => parser.parse('<html>none</html>', 'https://www.threads.com/@a/post/b'),
      throwsA(isA<FormatException>()),
    );
  });

  test('keeps only video when private capture exposes video plus poster images', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'pageUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/poster.jpg?x=1'},
        {'kind': 'video', 'url': 'https://scontent.cdninstagram.com/o1/v/t16/f2/m86/AQvideo.mp4?efg=eyJ2ZW5jb2RlX3RhZyI6Inhwdl9wcm9ncmVzc2l2ZS5GQUtFIn0'},
      ],
      'html': '',
    });
    final post = parser.parse(source, 'https://www.threads.com/share/BBhSFQy7Fx/');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.video);
  });

}
