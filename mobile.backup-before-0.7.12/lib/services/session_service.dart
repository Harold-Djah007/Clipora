import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionService {
  static const _storage = FlutterSecureStorage();
  static const _savedAtKey = 'threads_session_saved_at';
  static const _cookiesKey = 'threads_session_cookie_snapshot';
  static final _cookieUrls = [
    WebUri('https://www.threads.com/'),
    WebUri('https://www.threads.net/'),
    WebUri('https://www.instagram.com/'),
  ];

  Future<bool> hasSession({int ttlHours = 24}) async {
    final saved = await _storage.read(key: _savedAtKey);
    if (saved == null) return false;
    final when = DateTime.tryParse(saved);
    if (when == null) return false;
    if (DateTime.now().difference(when).inHours >= ttlHours) {
      await clearSession();
      return false;
    }

    final names = <String>{};
    for (final url in _cookieUrls) {
      try {
        final cookies = await CookieManager.instance().getCookies(url: url);
        names.addAll(cookies.map((c) => c.name));
      } catch (_) {}
    }
    return names.contains('sessionid') || names.contains('ds_user_id');
  }

  Future<void> snapshot() async {
    final safeNames = {'sessionid', 'ds_user_id', 'csrftoken', 'mid', 'ig_did'};
    final snapshot = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final url in _cookieUrls) {
      try {
        final cookies = await CookieManager.instance().getCookies(url: url);
        for (final c in cookies.where((c) => safeNames.contains(c.name))) {
          final key = '${c.domain}|${c.name}';
          if (!seen.add(key)) continue;
          snapshot.add({
            'name': c.name,
            'domain': c.domain,
            'expires': c.expiresDate,
          });
        }
      } catch (_) {}
    }

    // Cookie VALUES stay in Android WebView's cookie jar. Secure storage keeps
    // only non-secret metadata so ThreadVault can show/expire session state.
    await _storage.write(key: _cookiesKey, value: jsonEncode(snapshot));
    await _storage.write(key: _savedAtKey, value: DateTime.now().toIso8601String());
  }

  Future<void> clearSession() async {
    await CookieManager.instance().deleteAllCookies();
    await _storage.delete(key: _savedAtKey);
    await _storage.delete(key: _cookiesKey);
  }

  Future<DateTime?> savedAt() async {
    final raw = await _storage.read(key: _savedAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
