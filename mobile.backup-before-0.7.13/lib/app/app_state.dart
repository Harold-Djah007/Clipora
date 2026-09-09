import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_models.dart';
import '../services/download_manager.dart';
import '../services/history_store.dart';
import '../services/session_service.dart';
import '../services/settings_store.dart';
import '../services/platform_services.dart';
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
  bool lastRunHadErrors = false;

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
    if (urls.isEmpty || busy) return;
    busy = true;
    lastRunHadErrors = false;
    status = 'Preparing ${urls.length} post${urls.length == 1 ? '' : 's'}…';
    await PlatformServices.startDownloadService(message: status!);
    notifyListeners();

    var mediaDone = 0;
    var failed = 0;
    final errors = <String>[];

    try {
      for (var postIndex = 0; postIndex < urls.length; postIndex++) {
        final url = urls[postIndex];
        status = 'Resolving post ${postIndex + 1} of ${urls.length}…';
        await PlatformServices.updateDownloadService(message: status!);
        notifyListeners();
        try {
          debugPrint('[ThreadVault] resolving: $url');
          final source = await sourceLoader(url);
          debugPrint('[ThreadVault] resolver source bytes=${source.length}');
          final post = parser.parse(source, url);
          debugPrint('[ThreadVault] parsed ${post.media.length} media item(s) for ${post.postId}');
          final result = await downloadManager.downloadPost(
            post,
            settings,
            onProgress: (c, total) {
              status = 'Saving media $c of $total from post ${postIndex + 1}…';
              unawaited(PlatformServices.updateDownloadService(message: status!));
              notifyListeners();
            },
          );
          mediaDone += result.length;
          final postFailures = result.where((r) => r.status == DownloadStatus.failed).toList();
          failed += postFailures.length;
          if (postFailures.isNotEmpty) {
            errors.addAll(postFailures.map((e) => e.error ?? 'Unknown download error'));
          }
        } catch (e, st) {
          debugPrint('[ThreadVault] post failed: $e\n$st');
          failed++;
          errors.add(e.toString().replaceFirst('FormatException: ', '').replaceFirst('Bad state: ', ''));
        }
      }

      history = await historyStore.load();
      lastRunHadErrors = failed > 0;
      if (failed == 0) {
        status = 'Saved $mediaDone media item${mediaDone == 1 ? '' : 's'} to your Gallery / Clipora folders';
      } else if (mediaDone > failed) {
        status = 'Saved ${mediaDone - failed} item${mediaDone - failed == 1 ? '' : 's'}; $failed failed. ${errors.first}';
      } else {
        status = 'Download failed: ${errors.isEmpty ? 'No media could be saved.' : errors.first}';
      }
    } finally {
      await PlatformServices.stopDownloadService();
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
