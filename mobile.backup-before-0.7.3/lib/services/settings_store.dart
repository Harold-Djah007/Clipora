import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String filenameTemplate;
  final bool includeCaption;
  final bool autoDeleteSession;
  final int sessionTtlHours;
  final bool wifiOnly;

  const AppSettings({
    this.filenameTemplate = '{author}_{postId}_{index}',
    this.includeCaption = true,
    this.autoDeleteSession = true,
    this.sessionTtlHours = 24,
    this.wifiOnly = false,
  });

  AppSettings copyWith({
    String? filenameTemplate,
    bool? includeCaption,
    bool? autoDeleteSession,
    int? sessionTtlHours,
    bool? wifiOnly,
  }) => AppSettings(
        filenameTemplate: filenameTemplate ?? this.filenameTemplate,
        includeCaption: includeCaption ?? this.includeCaption,
        autoDeleteSession: autoDeleteSession ?? this.autoDeleteSession,
        sessionTtlHours: sessionTtlHours ?? this.sessionTtlHours,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );
}

class SettingsStore {
  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      filenameTemplate: p.getString('filenameTemplate') ?? '{author}_{postId}_{index}',
      includeCaption: p.getBool('includeCaption') ?? true,
      autoDeleteSession: p.getBool('autoDeleteSession') ?? true,
      sessionTtlHours: p.getInt('sessionTtlHours') ?? 24,
      wifiOnly: p.getBool('wifiOnly') ?? false,
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('filenameTemplate', s.filenameTemplate);
    await p.setBool('includeCaption', s.includeCaption);
    await p.setBool('autoDeleteSession', s.autoDeleteSession);
    await p.setInt('sessionTtlHours', s.sessionTtlHours);
    await p.setBool('wifiOnly', s.wifiOnly);
  }
}
