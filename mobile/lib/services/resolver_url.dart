class ResolverUrl {
  /// Optional production resolver baked into release builds.
  ///
  /// Build a stress-free APK with:
  ///   flutter build apk --release --dart-define=CLIPORA_RESOLVER_URL=https://your-resolver-domain
  /// When this is blank, Settings can still provide a hosted/LAN resolver.
  static const defaultValue = String.fromEnvironment('CLIPORA_RESOLVER_URL', defaultValue: '');

  static const fallbacks = [
    'http://127.0.0.1:8010',
    'http://127.0.0.1:8011',
    'http://127.0.0.1:8765',
    'http://10.0.2.2:8010',
  ];

  static bool isConfigured(String raw) => normalize(raw).isNotEmpty;

  static String normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return defaultValue.trim();
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static bool isAllowed(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return true;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    return isPrivateHost(uri.host);
  }

  static bool isPrivateHost(String host) {
    final value = host.toLowerCase();
    if (value == 'localhost' || value == '::1') return true;
    final parts = value.split('.');
    if (parts.length != 4) return false;
    final nums = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) return false;
      nums.add(number);
    }
    final a = nums[0];
    final b = nums[1];
    if (a == 127 || a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static List<String> candidates(String preferred) {
    final first = normalize(preferred);
    if (first.isEmpty) return const [];

    final out = <String>[];
    if (isAllowed(first)) out.add(first);
    for (final item in fallbacks) {
      if (!out.contains(item)) out.add(item);
    }
    return out;
  }
}
