import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/media_models.dart';
import '../services/download_manager.dart';
import '../services/history_store.dart';
import '../services/session_service.dart';
import '../services/settings_store.dart';
import '../services/platform_services.dart';
import '../services/threads_parser.dart';
import '../services/universal_capture_parser.dart';
import '../services/universal_platform_detector.dart';
import '../services/universal_resolver_service.dart';

class AppState extends ChangeNotifier {
  Timer? _sessionTimer;
  final parser = ThreadsParser();
  final captureParser = UniversalCaptureParser();
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

  /// Clipora 2.0 first stage: inspect links and return a picker-ready media plan.
  ///
  /// This is deliberately separated from saving so the UX no longer feels like the
  /// old one-button flow. Threads still routes through the existing local parser;
  /// non-Threads uses the optional resolver first, then Field Mode capture.
  Future<List<ResolvedPost>> scanForMedia(
    List<String> urls, {
    required Future<String> Function(String url) sourceLoader,
  }) async {
    if (urls.isEmpty) return const [];

    activeJobs += 1;
    busy = activeJobs > 0;
    lastRunHadErrors = false;
    lastRunSaved = 0;
    status = 'Analyzing ${urls.length} link${urls.length == 1 ? '' : 's'}…';
    notifyListeners();

    final posts = <ResolvedPost>[];
    final errors = <String>[];

    try {
      for (var i = 0; i < urls.length; i++) {
        final url = urls[i];
        final platform = UniversalPlatformDetector.detect(url);
        status = 'Scanning ${platform.label} ${i + 1}/${urls.length}…';
        notifyListeners();

        try {
          if (!platform.isSupported) {
            throw StateError('Unsupported link. Clipora supports ${UniversalPlatformDetector.supportedLabel}.');
          }
          debugPrint('[Clipora] 2.0 analyze ${platform.label}: $url');
          final post = await _resolvePost(url, platform, sourceLoader);
          debugPrint('[Clipora] 2.0 picker found ${post.media.length} media item(s) for ${post.postId} via ${platform.label}');
          posts.add(post);
        } catch (e, st) {
          debugPrint('[Clipora] 2.0 scan failed: $e\n$st');
          errors.add(_friendlyError(e));
        }
      }

      lastRunHadErrors = errors.isNotEmpty;
      if (posts.isEmpty) {
        status = 'Scan failed: ${errors.isEmpty ? 'No media was found.' : errors.first}';
        throw StateError(status!);
      }

      final totalMedia = posts.fold<int>(0, (sum, post) => sum + post.media.length);
      status = errors.isEmpty
          ? 'Ready: found $totalMedia media item${totalMedia == 1 ? '' : 's'}.'
          : 'Ready: found $totalMedia item${totalMedia == 1 ? '' : 's'}; ${errors.length} link${errors.length == 1 ? '' : 's'} failed.';
      return posts;
    } finally {
      activeJobs = activeJobs > 0 ? activeJobs - 1 : 0;
      busy = activeJobs > 0;
      notifyListeners();
    }
  }

  /// Clipora 2.0 second stage: save the picker-selected media plan.
  Future<bool> saveResolvedMedia(List<ResolvedPost> posts) async {
    final filtered = posts.where((post) => post.media.isNotEmpty).toList(growable: false);
    if (filtered.isEmpty) return false;

    activeJobs += 1;
    busy = activeJobs > 0;
    lastRunHadErrors = false;
    lastRunSaved = 0;
    status = 'Saving selected media…';
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
              status = 'Saving $completed of $total selected ${platform.label} item${total == 1 ? '' : 's'}…';
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
          debugPrint('[Clipora] 2.0 save failed: $e\n$st');
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
        status = 'Save failed: ${errors.isEmpty ? 'No selected media could be saved.' : errors.first}';
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

  /// Compatibility wrapper for older screens/tests. New Clipora 2.0 UI uses
  /// scanForMedia() and saveResolvedMedia() as two separate steps.
  Future<bool> resolveAndDownload(
    List<String> urls, {
    required Future<String> Function(String url) sourceLoader,
  }) async {
    final posts = await scanForMedia(urls, sourceLoader: sourceLoader);
    return saveResolvedMedia(posts);
  }

  Future<ResolvedPost> _resolvePost(
    String url,
    PlatformMatch platform,
    Future<String> Function(String url) sourceLoader,
  ) async {
    if (platform.isThreads) {
      return _resolveWithCapture(url, platform, sourceLoader, reason: 'Capturing Threads media quietly on this phone…');
    }

    if (universalResolver.hasConfiguredBackend) {
      try {
        status = 'Resolver Boost: extracting ${platform.label} media…';
        await PlatformServices.updateDownloadService(message: status!);
        notifyListeners();
        return await universalResolver.resolve(url);
      } catch (error) {
        debugPrint('[Clipora] optional backend unavailable for ${platform.label}, using phone capture: $error');
      }
    }

    return _resolveWithCapture(
      url,
      platform,
      sourceLoader,
      reason: 'Field Mode: capturing ${platform.label} media on this phone…',
    );
  }

  Future<ResolvedPost> _resolveWithCapture(
    String url,
    PlatformMatch platform,
    Future<String> Function(String url) sourceLoader, {
    required String reason,
  }) async {
    status = reason;
    notifyListeners();

    final source = await sourceLoader(url);
    debugPrint('[Clipora] ${platform.label} field capture source bytes=${source.length}');
    if (platform.isThreads) {
      return parser.parse(source, url);
    }
    return captureParser.parse(source, url, platform);
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
