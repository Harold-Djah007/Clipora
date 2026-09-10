import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/media_models.dart';
import '../services/download_manager.dart';
import '../services/history_store.dart';
import '../services/platform_services.dart';
import '../services/session_service.dart';
import '../services/settings_store.dart';
import '../services/universal_platform_detector.dart';
import '../services/universal_resolver_service.dart';

class AppState extends ChangeNotifier {
  Timer? _sessionTimer;
  final historyStore = HistoryStore();
  final sessionService = SessionService();
  late final DownloadManager downloadManager = DownloadManager(historyStore);
  final settingsStore = SettingsStore();
  late UniversalResolverService universalResolver = UniversalResolverService();

  AppSettings settings = const AppSettings();
  List<DownloadRecord> history = [];
  bool sessionConnected = false;
  bool busy = false;
  int activeJobs = 0;
  int lastRunSaved = 0;
  String? status;
  bool lastRunHadErrors = false;

  Future<void> init() async {
    settings = await settingsStore.load();
    universalResolver = UniversalResolverService(preferredBaseUrl: settings.resolverUrl);
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
    universalResolver = UniversalResolverService(preferredBaseUrl: next.resolverUrl);
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

  /// Builds a save plan from pasted links using the hosted resolver only.
  ///
  /// Clipora Instant no longer opens a phone WebView for Snapchat, Threads,
  /// TikTok, Instagram, X, Pinterest, Facebook, or YouTube. Every supported
  /// platform is automatic: paste/share -> resolver extracts -> APK saves.
  Future<List<ResolvedPost>> scanForMedia(
    List<String> urls, {
    required Future<String> Function(String url) sourceLoader,
  }) async {
    if (urls.isEmpty) return const [];

    activeJobs += 1;
    busy = activeJobs > 0;
    lastRunHadErrors = false;
    lastRunSaved = 0;
    status = 'Preparing ${urls.length} link${urls.length == 1 ? '' : 's'}…';
    notifyListeners();

    final posts = <ResolvedPost>[];
    final errors = <String>[];

    try {
      for (var i = 0; i < urls.length; i++) {
        final url = urls[i];
        final platform = UniversalPlatformDetector.detect(url);
        status = 'Resolving ${platform.label} ${i + 1}/${urls.length}…';
        notifyListeners();

        try {
          if (!platform.isSupported) {
            throw StateError('Unsupported link. Clipora supports ${UniversalPlatformDetector.supportedLabel}.');
          }
          debugPrint('[Clipora] instant resolver-only ${platform.label}: $url');
          final post = await _resolvePost(url, platform);
          debugPrint('[Clipora] resolver found ${post.media.length} media item(s) for ${post.postId} via ${platform.label}');
          posts.add(post);
        } catch (e, st) {
          debugPrint('[Clipora] resolver-only link failed: $e\n$st');
          errors.add(_friendlyError(e));
        }
      }

      lastRunHadErrors = errors.isNotEmpty;
      if (posts.isEmpty) {
        status = 'Download failed: ${errors.isEmpty ? 'No media was found.' : errors.first}';
        throw StateError(status!);
      }

      final totalMedia = posts.fold<int>(0, (sum, post) => sum + post.media.length);
      status = errors.isEmpty
          ? 'Found $totalMedia media item${totalMedia == 1 ? '' : 's'}. Saving now…'
          : 'Found $totalMedia item${totalMedia == 1 ? '' : 's'}; ${errors.length} link${errors.length == 1 ? '' : 's'} failed. Saving what worked…';
      return posts;
    } finally {
      activeJobs = activeJobs > 0 ? activeJobs - 1 : 0;
      busy = activeJobs > 0;
      notifyListeners();
    }
  }

  Future<bool> saveResolvedMedia(List<ResolvedPost> posts) async {
    final filtered = posts.where((post) => post.media.isNotEmpty).toList(growable: false);
    if (filtered.isEmpty) return false;

    activeJobs += 1;
    busy = activeJobs > 0;
    lastRunHadErrors = false;
    lastRunSaved = 0;
    status = 'Saving media…';
    await PlatformServices.startDownloadService(message: status!);
    notifyListeners();

    var saved = 0;
    var failed = 0;
    final errors = <String>[];

    try {
      for (var postIndex = 0; postIndex < filtered.length; postIndex++) {
        final post = filtered[postIndex];
        final platform = UniversalPlatformDetector.detect(post.sourceUrl);
        try {
          status = 'Saving ${platform.label} ${postIndex + 1}/${filtered.length}…';
          await PlatformServices.updateDownloadService(message: status!);
          notifyListeners();

          final result = await downloadManager.downloadPost(
            post,
            settings,
            onProgress: (completed, total) {
              status = 'Saving $completed of $total ${platform.label} item${total == 1 ? '' : 's'}…';
              unawaited(PlatformServices.updateDownloadService(message: status!));
              notifyListeners();
            },
          );

          final postFailures = result.where((record) => record.status == DownloadStatus.failed).toList();
          final postSaved = result.length - postFailures.length;
          saved += postSaved;
          failed += postFailures.length;
          if (postFailures.isNotEmpty) {
            errors.addAll(postFailures.map((record) => record.error ?? 'Unknown download error'));
          }
        } catch (e, st) {
          debugPrint('[Clipora] instant save failed: $e\n$st');
          failed++;
          errors.add(_friendlyError(e));
        }
      }

      history = await historyStore.load();
      lastRunHadErrors = failed > 0;
      lastRunSaved = saved;
      final completedOk = saved > 0;
      if (failed == 0) {
        status = 'Saved $saved media item${saved == 1 ? '' : 's'} to Clipora.';
      } else if (saved > 0) {
        status = 'Saved $saved; $failed failed. ${errors.first}';
      } else {
        status = 'Save failed: ${errors.isEmpty ? 'No media could be saved.' : errors.first}';
      }

      await PlatformServices.showDownloadComplete(
        title: completedOk ? 'Clipora saved media' : 'Clipora finished with errors',
        message: status!,
        success: completedOk,
      );
      return completedOk;
    } finally {
      activeJobs = activeJobs > 0 ? activeJobs - 1 : 0;
      busy = activeJobs > 0;
      if (busy) {
        await PlatformServices.updateDownloadService(message: '$activeJobs Clipora task${activeJobs == 1 ? '' : 's'} still running…');
      } else {
        await PlatformServices.stopDownloadService();
      }
      notifyListeners();
    }
  }

  Future<bool> resolveAndDownload(
    List<String> urls, {
    required Future<String> Function(String url) sourceLoader,
  }) async {
    final posts = await scanForMedia(urls, sourceLoader: sourceLoader);
    return saveResolvedMedia(posts);
  }

  Future<ResolvedPost> _resolvePost(String url, PlatformMatch platform) async {
    if (!universalResolver.hasConfiguredBackend) {
      throw StateError(
        'Clipora Instant needs a hosted resolver URL to stay fully automatic. No platform uses the old phone page-capture flow anymore, including Threads. Add a resolver in Settings or build the APK with --dart-define=CLIPORA_RESOLVER_URL=https://your-resolver-domain.',
      );
    }

    try {
      status = 'Clipora Resolver: extracting ${platform.label} media…';
      await PlatformServices.updateDownloadService(message: status!);
      notifyListeners();
      return await universalResolver.resolve(url);
    } catch (error) {
      throw StateError('Resolver failed for ${platform.label}: ${_friendlyError(error)}');
    }
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('StateError: ', '');

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
}
