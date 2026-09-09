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

  test('does not complete video posts from poster-only runtime image when html has video', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'pageUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/low_quality_poster.jpg?x=1'},
      ],
      'html': r'{"video_versions":[{"width":360,"height":640,"url":"https:\/\/scontent.cdninstagram.com\/o1\/v\/t16\/f2\/m86\/low.mp4?x=1"},{"width":1080,"height":1920,"url":"https:\/\/scontent.cdninstagram.com\/o1\/v\/t16\/f2\/m86\/hd.mp4?x=2"}]}',
    });
    final post = parser.parse(source, 'https://www.threads.com/share/BBhSFQy7Fx/');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.video);
    expect(post.media.single.url, contains('hd.mp4'));
  });

  test('rejects poster-only result when resolver says this is a video post', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'pageUrl': 'https://www.threads.com/@whitemansdaughter/post/Dbd6IzSCLAa',
      'hasVideo': true,
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/low_quality_poster.jpg?x=1'},
      ],
      'html': '<html>boot payload mentions video_versions but no signed mp4 yet</html>',
    });
    expect(
      () => parser.parse(source, 'https://www.threads.com/share/BBhSFQy7Fx/'),
      throwsA(isA<FormatException>()),
    );
  });

  test('still accepts real photo posts without video hints', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@alice/post/PHOTO1',
      'pageUrl': 'https://www.threads.com/@alice/post/PHOTO1',
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/photo.jpg?x=1', 'width': 1440, 'height': 1440},
      ],
      'html': '<html><article>photo only</article></html>',
    });
    final post = parser.parse(source, 'https://www.threads.com/@alice/post/PHOTO1');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.image);
  });

  test('rejects share-link image-only snapshots unless user chooses Photos', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@whitemansdaughter/post/DYidInrn91b',
      'pageUrl': 'https://www.threads.com/@whitemansdaughter/post/DYidInrn91b',
      'captureMode': 'hidden',
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/poster.jpg?x=1'},
      ],
      'html': '<html>poster only</html>',
    });
    expect(
      () => parser.parse(source, 'https://www.threads.com/share/BBhSFQy7Fx/'),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts image-only share snapshot after explicit Photos capture', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@alice/post/PHOTO_SHARE',
      'pageUrl': 'https://www.threads.com/@alice/post/PHOTO_SHARE',
      'captureMode': 'privatePhoto',
      'runtimeMedia': [
        {'kind': 'image', 'url': 'https://scontent.cdninstagram.com/v/t51.29350-15/photo.jpg?x=1', 'width': 1440, 'height': 1440},
      ],
      'html': '<html>photo only</html>',
    });
    final post = parser.parse(source, 'https://www.threads.com/share/photo123/');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.image);
  });

  test('does not save one played Threads video twice when html has another variant', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@whitemansdaughter/post/DYcaQwFgZos',
      'pageUrl': 'https://www.threads.com/@whitemansdaughter/post/DYcaQwFgZos',
      'runtimeMedia': [
        {
          'kind': 'video',
          'url': 'https://instagram.facc6-1.fna.fbcdn.net/o1/v/t16/f1/m82/single-video.mp4?runtime=1',
          'width': 540,
          'height': 960,
        },
      ],
      'html': r'{"video_versions":[{"width":540,"height":960,"url":"https:\/\/instagram.facc6-1.fna.fbcdn.net\/o1\/v\/t16\/f1\/m82\/single-video.mp4?progressive=1"}]}',
      'hasVideo': true,
    });

    final post = parser.parse(source, 'https://www.threads.com/@whitemansdaughter/post/DYcaQwFgZos');
    expect(post.media, hasLength(1));
    expect(post.media.single.kind, MediaKind.video);
    expect(post.media.single.url, contains('runtime=1'));
  });

  test('keeps distinct runtime videos when Threads really exposes more than one', () {
    final source = jsonEncode({
      'canonicalUrl': 'https://www.threads.com/@creator/post/ABC123',
      'pageUrl': 'https://www.threads.com/@creator/post/ABC123',
      'runtimeMedia': [
        {'kind': 'video', 'url': 'https://instagram.facc6-1.fna.fbcdn.net/o1/v/t16/f1/m82/first.mp4?sig=1'},
        {'kind': 'video', 'url': 'https://instagram.facc6-1.fna.fbcdn.net/o1/v/t16/f1/m82/second.mp4?sig=2'},
      ],
      'html': '<html></html>',
      'hasVideo': true,
    });

    final post = parser.parse(source, 'https://www.threads.com/@creator/post/ABC123');
    expect(post.media, hasLength(2));
    expect(post.media.every((item) => item.kind == MediaKind.video), isTrue);
  });
}
