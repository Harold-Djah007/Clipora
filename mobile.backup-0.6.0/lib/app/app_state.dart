import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_models.dart';
import '../services/download_manager.dart';
import '../services/history_store.dart';
import '../services/session_service.dart';
import '../services/settings_store.dart';
import '../services/threads_parser.dart';

class AppState extends ChangeNotifier {
  Timer? _sessionTimer;
  final parser = ThreadsParser();
  final historyStore = HistoryStore();
  final sessionService = SessionService();
  late final DownloadManager downloadManager = DownloadManager(historyStore);
  final settingsStore = SettingsStore();

  AppSettings settings = const AppSettings();
  List<DownloadRecord> history = [];
  bool sessionConnected = false;
  bool busy = false;
  String? status;

  Future<void> init() async {
    settings = await settingsStore.load();
    history = await historyStore.load();
    sessionConnected = await sessionService.hasSession(ttlHours: settings.sessionTtlHours);
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (settings.autoDeleteSession) {
        final active = await sessionService.hasSession(ttlHours: settings.sessionTtlHours);
        if (active != sessionConnected) {
          sessionConnected = active;
          notifyListeners();
        }
      }
    });
    notifyListeners();
  }

  Future<void> setSettings(AppSettings next) async {
    settings = next;
    await settingsStore.save(next);
    if (next.autoDeleteSession) {
      sessionConnected = await sessionService.hasSession(ttlHours: next.sessionTtlHours);
    }
    notifyListeners();
  }

  Future<void> refreshSession() async {
    await sessionService.snapshot();
    sessionConnected = await sessionService.hasSession(ttlHours: settings.sessionTtlHours);
    notifyListeners();
  }

  Future<void> disconnect() async {
    await sessionService.clearSession();
    sessionConnected = false;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await historyStore.clear();
    notifyListeners();
  }

  Future<void> resolveAndDownload(
    List<String> urls, {
    required Future<String> Function(String url) sourceLoader,
  }) async {
    if (urls.isEmpty) return;
    busy = true;
    status = 'Preparing ${urls.length} post${urls.length == 1 ? '' : 's'}…';
    notifyListeners();
    var done = 0;
    try {
      for (final url in urls) {
        status = 'Opening post ${done + 1} of ${urls.length}…';
        notifyListeners();
        final source = await sourceLoader(url);
        final post = parser.parse(source, url);
        await downloadManager.downloadPost(post, settings, onProgress: (c, total) {
          status = 'Downloading $c of $total media items…';
          notifyListeners();
        });
        done++;
      }
      history = await historyStore.load();
      status = 'Finished $done post${done == 1 ? '' : 's'}';
    } catch (e) {
      status = 'Could not finish: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }


  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
