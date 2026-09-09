import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionService {
  static const _storage = FlutterSecureStorage();
  static const _savedAtKey = 'threads_session_saved_at';
  static const _cookiesKey = 'threads_session_cookie_snapshot';

  Future<bool> hasSession({int ttlHours = 24}) async {
    final saved = await _storage.read(key: _savedAtKey);
    if (saved == null) return false;
    final when = DateTime.tryParse(saved);
    if (when == null) return false;
    if (DateTime.now().difference(when).inHours >= ttlHours) {
      await clearSession();
      return false;
    }
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://www.threads.com/'),
    );
    return cookies.any((c) => c.name == 'sessionid' || c.name == 'ds_user_id');
  }

  Future<void> snapshot() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://www.threads.com/'),
    );
    final safeNames = {'sessionid', 'ds_user_id', 'csrftoken', 'mid', 'ig_did'};
    final snapshot = cookies
        .where((c) => safeNames.contains(c.name))
        .map((c) => {'name': c.name, 'domain': c.domain, 'expires': c.expiresDate})
        .toList();
    // Values remain inside the WebView cookie jar. Only non-secret metadata is
    // kept in secure storage to track state/expiry.
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
