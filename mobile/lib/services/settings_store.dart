import 'package:shared_preferences/shared_preferences.dart';

import 'resolver_url.dart';

class AppSettings {
  final String filenameTemplate;
  final bool includeCaption;
  final bool wifiOnly;
  final int maxConcurrentDownloads;
  final String resolverUrl;

  const AppSettings({
    this.filenameTemplate = '{author}_{postId}_{index}',
    this.includeCaption = true,
    this.wifiOnly = false,
    this.maxConcurrentDownloads = 5,
    this.resolverUrl = ResolverUrl.defaultValue,
  });

  AppSettings copyWith({
    String? filenameTemplate,
    bool? includeCaption,
    bool? wifiOnly,
    int? maxConcurrentDownloads,
    String? resolverUrl,
  }) => AppSettings(
        filenameTemplate: filenameTemplate ?? this.filenameTemplate,
        includeCaption: includeCaption ?? this.includeCaption,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
        resolverUrl: resolverUrl ?? this.resolverUrl,
      );
}

class SettingsStore {
  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    var lanes = p.getInt('maxConcurrentDownloads');
    final turboMigrated = p.getBool('clipora080TurboMigrated') ?? false;
    if (!turboMigrated && (lanes == null || lanes < 5)) {
      lanes = 5;
      await p.setInt('maxConcurrentDownloads', lanes);
      await p.setBool('clipora080TurboMigrated', true);
    }

    var resolverUrl = p.getString('resolverUrl') ?? ResolverUrl.defaultValue;
    final bundled = ResolverUrl.normalize(ResolverUrl.defaultValue);
    final savedUri = Uri.tryParse(ResolverUrl.normalize(resolverUrl));
    if (bundled.isNotEmpty && savedUri != null && ResolverUrl.isPrivateHost(savedUri.host)) {
      // A field APK must not retain 127.0.0.1/LAN settings from USB testing.
      resolverUrl = bundled;
      await p.setString('resolverUrl', resolverUrl);
    }

    return AppSettings(
      filenameTemplate: p.getString('filenameTemplate') ?? '{author}_{postId}_{index}',
      includeCaption: p.getBool('includeCaption') ?? true,
      wifiOnly: p.getBool('wifiOnly') ?? false,
      maxConcurrentDownloads: (lanes ?? 5).clamp(1, 6).toInt(),
      resolverUrl: resolverUrl,
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('filenameTemplate', s.filenameTemplate);
    await p.setBool('includeCaption', s.includeCaption);
    await p.setBool('wifiOnly', s.wifiOnly);
    await p.setInt('maxConcurrentDownloads', s.maxConcurrentDownloads.clamp(1, 6).toInt());
    await p.setString('resolverUrl', s.resolverUrl);
    await p.setBool('clipora080TurboMigrated', true);
  }
}
