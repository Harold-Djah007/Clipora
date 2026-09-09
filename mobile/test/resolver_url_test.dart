import 'package:flutter_test/flutter_test.dart';
import 'package:threadvault/services/resolver_url.dart';

void main() {
  test('allows localhost, emulator, and RFC1918 HTTP resolver URLs', () {
    expect(ResolverUrl.isAllowed('http://127.0.0.1:8010'), isTrue);
    expect(ResolverUrl.isAllowed('http://localhost:8010'), isTrue);
    expect(ResolverUrl.isAllowed('http://10.0.2.2:8010'), isTrue);
    expect(ResolverUrl.isAllowed('http://192.168.1.10:8010'), isTrue);
    expect(ResolverUrl.isAllowed('http://10.0.0.5:8010'), isTrue);
    expect(ResolverUrl.isAllowed('http://172.16.4.2:8010'), isTrue);
  });

  test('rejects public HTTP resolver hosts', () {
    expect(ResolverUrl.isAllowed('http://example.com:8010'), isFalse);
    expect(ResolverUrl.isAllowed('ftp://192.168.1.10:8010'), isFalse);
  });

  test('puts the preferred LAN URL first', () {
    final urls = ResolverUrl.candidates('http://192.168.0.20:8010');
    expect(urls.first, 'http://192.168.0.20:8010');
    expect(urls, contains('http://127.0.0.1:8010'));
  });
}
