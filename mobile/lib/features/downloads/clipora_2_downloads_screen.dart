import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../models/media_models.dart';
import '../../services/platform_services.dart';
import '../../services/universal_platform_detector.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/threadvault_mark.dart';

enum _InstantStage { idle, saving, done, error }

class Clipora2DownloadsScreen extends StatefulWidget {
  const Clipora2DownloadsScreen({super.key});

  @override
  State<Clipora2DownloadsScreen> createState() => _Clipora2DownloadsScreenState();
}

class _Clipora2DownloadsScreenState extends State<Clipora2DownloadsScreen> with WidgetsBindingObserver {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final List<_CaptureRequest> _captureQueue = [];

  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  String? clipboardUrl;
  String? errorText;
  String? lastAutoFingerprint;
  _CaptureRequest? activeCapture;
  _InstantStage stage = _InstantStage.idle;
  Timer? autoTimer;
  Timer? doneTimer;
  bool showDone = false;
  int captureSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _readSharedUrl(autoStart: true);
      await _readClipboard(autoStart: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    autoTimer?.cancel();
    doneTimer?.cancel();
    scrollController.dispose();
    final pending = [if (activeCapture != null) activeCapture!, ..._captureQueue];
    for (final request in pending) {
      request.timeout?.cancel();
      if (!request.completer.isCompleted) {
        request.completer.completeError(StateError('Clipora closed before capture finished.'));
      }
    }
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_readSharedUrl(autoStart: true));
      unawaited(_readClipboard(autoStart: false));
    }
  }

  List<String> _extractUrls(String raw) {
    final seen = <String>{};
    final urls = <String>[];
    for (final match in _urlPattern.allMatches(raw)) {
      final value = match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
      if (seen.add(value)) urls.add(value);
    }
    return urls.take(20).toList(growable: false);
  }

  String _fingerprint(List<String> urls) => urls.map((url) => url.trim()).join('\n');

  Future<void> _readSharedUrl({required bool autoStart}) async {
    final shared = await PlatformServices.takeSharedUrl();
    if (!mounted || shared == null) return;
    final urls = _extractUrls(shared);
    if (urls.isEmpty) return;
    setState(() {
      controller.text = urls.join('\n');
      clipboardUrl = urls.first;
      errorText = null;
      stage = _InstantStage.idle;
    });
    if (autoStart) _scheduleInstantDownload();
  }

  Future<void> _readClipboard({required bool autoStart}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final urls = _extractUrls(data?.text ?? '');
    if (!mounted) return;
    setState(() {
      clipboardUrl = urls.isEmpty ? null : urls.first;
      if (controller.text.trim().isEmpty && urls.isNotEmpty) {
        controller.text = urls.join('\n');
        errorText = null;
        stage = _InstantStage.idle;
      }
    });
    if (autoStart && urls.isNotEmpty && controller.text.contains(urls.first)) {
      _scheduleInstantDownload();
    }
  }

  void _onInputChanged() {
    setState(() {
      errorText = null;
      if (_extractUrls(controller.text).isEmpty) stage = _InstantStage.idle;
    });
    _scheduleInstantDownload();
  }

  void _scheduleInstantDownload() {
    autoTimer?.cancel();
    final urls = _extractUrls(controller.text);
    if (urls.isEmpty || context.read<AppState>().busy) return;
    autoTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) unawaited(_downloadNow());
    });
  }

  Future<void> _downloadNow({bool force = false}) async {
    final submitted = controller.text;
    final urls = _extractUrls(submitted);
    if (urls.isEmpty) {
      _snack('Paste or share a supported social link first.');
      return;
    }

    final fingerprint = _fingerprint(urls);
    if (!force && lastAutoFingerprint == fingerprint) return;
    lastAutoFingerprint = fingerprint;
    autoTimer?.cancel();

    HapticFeedback.mediumImpact();
    setState(() {
      stage = _InstantStage.saving;
      errorText = null;
    });

    try {
      final ok = await context.read<AppState>().resolveAndDownload(urls, sourceLoader: _captureInBackground);
      if (!mounted) return;
      if (ok) {
        setState(() {
          if (controller.text == submitted) {
            controller.clear();
            clipboardUrl = null;
          }
          stage = _InstantStage.done;
          errorText = null;
          lastAutoFingerprint = null;
        });
        _flashDone();
      } else {
        setState(() {
          stage = _InstantStage.error;
          errorText = context.read<AppState>().status ?? 'Clipora could not save media from this link.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        stage = _InstantStage.error;
        errorText = _cleanError(error);
      });
    }
  }

  Future<String> _captureInBackground(String url) {
    final request = _CaptureRequest(id: captureSeq++, url: url, completer: Completer<String>());
    request.timeout = Timer(const Duration(seconds: 46), () {
      _completeCapture(
        request,
        error: StateError('Field capture timed out before the page exposed real media. Open it once in Access, let it play, then retry.'),
      );
    });
    _captureQueue.add(request);
    _pumpCaptureQueue();
    return request.completer.future;
  }

  void _pumpCaptureQueue() {
    if (!mounted || activeCapture != null || _captureQueue.isEmpty) return;
    setState(() => activeCapture = _captureQueue.removeAt(0));
  }

  void _completeCapture(_CaptureRequest request, {String? source, Object? error}) {
    request.timeout?.cancel();
    _captureQueue.remove(request);
    if (activeCapture != request) return;
    if (!request.completer.isCompleted) {
      if (source != null && source.isNotEmpty) {
        request.completer.complete(source);
      } else {
        request.completer.completeError(error ?? StateError('Field capture ended before media was found.'));
      }
    }
    if (!mounted) return;
    setState(() => activeCapture = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpCaptureQueue());
  }

  void _completeActiveCapture({String? source, Object? error}) {
    final request = activeCapture;
    if (request == null) return;
    _completeCapture(request, source: source, error: error);
  }

  void _flashDone() {
    doneTimer?.cancel();
    setState(() => showDone = true);
    doneTimer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) setState(() => showDone = false);
    });
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  String _cleanError(Object error) => error
      .toString()
      .replaceFirst('StateError: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final urls = _extractUrls(controller.text);
    final matches = UniversalPlatformDetector.detectAll(urls);
    final hasBackend = app.universalResolver.hasConfiguredBackend;
    final recent = app.history.take(5).toList();
    final busy = app.busy || stage == _InstantStage.saving;

    return CliporaPage(
      padding: EdgeInsets.zero,
      child: Stack(children: [
        const Positioned.fill(child: _InstantBackground()),
        Positioned.fill(
          child: ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 118),
            children: [
              _Header(hasBackend: hasBackend),
              const SizedBox(height: 18),
              _PastePanel(
                controller: controller,
                urlCount: urls.length,
                matches: matches,
                hasBackend: hasBackend,
                busy: busy,
                clipboardUrl: clipboardUrl,
                onChanged: _onInputChanged,
                onPaste: () async {
                  await _readClipboard(autoStart: true);
                  if (_extractUrls(controller.text).isNotEmpty) _scheduleInstantDownload();
                },
                onClear: () {
                  autoTimer?.cancel();
                  setState(() {
                    controller.clear();
                    errorText = null;
                    lastAutoFingerprint = null;
                    stage = _InstantStage.idle;
                  });
                },
                onDownload: busy ? null : () => _downloadNow(force: true),
              ),
              const SizedBox(height: 14),
              _StatusPanel(stage: stage, status: app.status, busy: busy, error: errorText),
              const SizedBox(height: 14),
              _RoutePanel(hasBackend: hasBackend, captureActive: activeCapture != null),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                _RecentPanel(recent: recent),
              ],
              const SizedBox(height: 18),
              const _BoundaryNote(),
            ],
          ),
        ),
        if (activeCapture != null)
          Positioned(
            left: 0,
            top: 0,
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height * .78,
            child: Opacity(
              opacity: 0.01,
              child: IgnorePointer(
                child: _HiddenCaptureHost(
                  key: ValueKey(activeCapture!.id),
                  url: activeCapture!.url,
                  onComplete: (source) => _completeActiveCapture(source: source),
                  onFailed: (error) => _completeActiveCapture(error: error),
                ),
              ),
            ),
          ),
        if (showDone) const Positioned.fill(child: IgnorePointer(child: _DoneOverlay())),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const ThreadVaultMark(size: 42, showGlow: false),
      const SizedBox(width: 12),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Clipora Instant', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
          SizedBox(height: 3),
          Text('Paste. Auto-download. Done.', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      ),
      _ModeBadge(hasBackend: hasBackend),
    ]);
  }
}

class _PastePanel extends StatelessWidget {
  const _PastePanel({
    required this.controller,
    required this.urlCount,
    required this.matches,
    required this.hasBackend,
    required this.busy,
    required this.clipboardUrl,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onDownload,
  });

  final TextEditingController controller;
  final int urlCount;
  final List<PlatformMatch> matches;
  final bool hasBackend;
  final bool busy;
  final String? clipboardUrl;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Just paste the link.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.9, height: 1.05)),
              const SizedBox(height: 8),
              Text(
                hasBackend
                    ? 'Resolver Boost starts immediately and saves every real media item.'
                    : 'Field Mode starts immediately on this phone. Add a hosted resolver later for the hardest services.',
                style: const TextStyle(color: Colors.white60, height: 1.35, fontSize: 13.2),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          _MetricTile(value: urlCount == 0 ? 'AUTO' : '$urlCount', label: urlCount == 1 ? 'link' : 'links'),
        ]),
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.newline,
          style: const TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Paste TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, or Threads…',
            prefixIcon: const Icon(Icons.link_rounded),
            suffixIcon: controller.text.trim().isEmpty
                ? IconButton(tooltip: 'Paste and download', onPressed: busy ? null : onPaste, icon: const Icon(Icons.content_paste_go_rounded))
                : IconButton(tooltip: 'Clear', onPressed: busy ? null : onClear, icon: const Icon(Icons.close_rounded)),
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: matches
                .map((match) => CliporaPill(
                      icon: match.icon,
                      label: match.label,
                      value: hasBackend && !match.isThreads ? 'resolver' : 'field',
                      color: match.accent,
                    ))
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton.icon(
            onPressed: onDownload,
            icon: Icon(busy ? Icons.downloading_rounded : Icons.bolt_rounded),
            label: Text(busy
                ? 'Downloading now…'
                : urlCount > 1
                    ? 'Download $urlCount links now'
                    : 'Download now'),
          ),
        ),
        if (clipboardUrl != null && !controller.text.contains(clipboardUrl!)) ...[
          const SizedBox(height: 10),
          TextButton.icon(onPressed: busy ? null : onPaste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Paste clipboard and download')),
        ],
      ]),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.stage, required this.status, required this.busy, required this.error});
  final _InstantStage stage;
  final String? status;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final failed = stage == _InstantStage.error || error != null;
    final done = stage == _InstantStage.done;
    final color = failed ? const Color(0xFFFCA5A5) : done ? const Color(0xFF86EFAC) : const Color(0xFF67E8F9);
    final icon = failed ? Icons.error_outline_rounded : done ? Icons.check_circle_rounded : busy ? Icons.downloading_rounded : Icons.touch_app_rounded;
    final message = error ?? status ?? 'Ready. Paste a link and Clipora starts automatically.';
    return _GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white70, height: 1.35, fontWeight: FontWeight.w700))),
        ]),
        if (busy) ...[
          const SizedBox(height: 12),
          const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 6)),
          const SizedBox(height: 8),
          const Text('No page switching. Clipora is resolving and saving quietly.', style: TextStyle(color: Colors.white54, fontSize: 12.5)),
        ],
      ]),
    );
  }
}

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.hasBackend, required this.captureActive});
  final bool hasBackend;
  final bool captureActive;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        const Expanded(child: _RouteStep(icon: Icons.travel_explore_rounded, title: 'Detect', body: 'auto')),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        Expanded(child: _RouteStep(icon: hasBackend ? Icons.cloud_sync_rounded : Icons.phone_android_rounded, title: hasBackend ? 'Resolve' : 'Capture', body: captureActive ? 'hidden' : (hasBackend ? 'boost' : 'field'))),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        const Expanded(child: _RouteStep(icon: Icons.download_done_rounded, title: 'Save', body: 'gallery')),
      ]),
    );
  }
}

class _RouteStep extends StatelessWidget {
  const _RouteStep({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, size: 20, color: const Color(0xFF8BE9E0)),
      const SizedBox(height: 6),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
      const SizedBox(height: 2),
      Text(body, style: const TextStyle(color: Colors.white45, fontSize: 11, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.recent});
  final List<DownloadRecord> recent;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent auto-saves', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 10),
      ...recent.map((item) {
        final success = item.status == DownloadStatus.completed;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(item.kind == MediaKind.video ? Icons.play_circle_outline_rounded : Icons.image_outlined, color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
              const SizedBox(width: 10),
              Expanded(child: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(success ? 'Saved' : 'Failed', style: TextStyle(fontSize: 12, color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5), fontWeight: FontWeight.w800)),
            ]),
          ),
        );
      }),
    ]);
  }
}

class _BoundaryNote extends StatelessWidget {
  const _BoundaryNote();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(15),
      child: const Text(
        'Clipora Instant saves public/shareable media and media you are authorized to access. No watermark-removal tool, no password collection, no private-access bypass. Threads keeps the existing capture path.',
        style: TextStyle(color: Colors.white54, height: 1.38, fontSize: 12.4),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(hasBackend ? Icons.cloud_done_rounded : Icons.phone_android_rounded, size: 14, color: const Color(0xFF8BE9E0)),
        const SizedBox(width: 6),
        Text(hasBackend ? 'Boost' : 'Field', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 70,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF00F2EA), Color(0xFF60A5FA)]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF06111C), fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: const TextStyle(color: Color(0xCC06111C), fontWeight: FontWeight.w900, fontSize: 11)),
      ]),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xCC0B1220),
        border: Border.all(color: Colors.white.withOpacity(.09)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.20), blurRadius: 28, offset: const Offset(0, 16))],
      ),
      child: child,
    );
  }
}

class _InstantBackground extends StatelessWidget {
  const _InstantBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF05070D), Color(0xFF07111F), Color(0xFF111827)]),
      ),
      child: Stack(children: [
        Positioned(top: -110, right: -80, width: 260, height: 260, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF00F2EA).withOpacity(.13)))),
        Positioned(bottom: 120, left: -100, width: 240, height: 240, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF8B5CF6).withOpacity(.11)))),
      ]),
    );
  }
}

class _DoneOverlay extends StatefulWidget {
  const _DoneOverlay();

  @override
  State<_DoneOverlay> createState() => _DoneOverlayState();
}

class _DoneOverlayState extends State<_DoneOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = Curves.easeOutCubic.transform(controller.value);
        final opacity = (1 - controller.value).clamp(0.0, 1.0).toDouble();
        return Center(
          child: Transform.scale(
            scale: .72 + value * .38,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF00F2EA).withOpacity(.18), border: Border.all(color: const Color(0xFF00F2EA).withOpacity(.55), width: 2)),
                child: const Icon(Icons.download_done_rounded, color: Colors.white, size: 58),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CaptureRequest {
  _CaptureRequest({required this.id, required this.url, required this.completer});
  final int id;
  final String url;
  final Completer<String> completer;
  Timer? timeout;
}

class _HiddenCaptureHost extends StatefulWidget {
  const _HiddenCaptureHost({super.key, required this.url, required this.onComplete, required this.onFailed});
  final String url;
  final ValueChanged<String> onComplete;
  final ValueChanged<Object> onFailed;

  @override
  State<_HiddenCaptureHost> createState() => _HiddenCaptureHostState();
}

class _HiddenCaptureHostState extends State<_HiddenCaptureHost> {
  InAppWebViewController? _controller;
  String? _lastSource;
  bool _done = false;
  Timer? _timeout;

  static const _js = r'''
    (function() {
      function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return u; } }
      const runtime = [];
      const seen = new Set();
      function push(kind, u, w, h) {
        if (!u) return;
        const url = abs(u);
        const key = kind + ':' + url;
        if (seen.has(key)) return;
        seen.add(key);
        runtime.push({kind: kind, url: url, width: w || null, height: h || null});
      }
      function classify(u, initiator) {
        const lower = (u || '').toLowerCase();
        const type = (initiator || '').toLowerCase();
        if (!lower || lower.indexOf('http') !== 0) return null;
        if (type === 'video' || lower.includes('.mp4') || lower.includes('mime=video') || lower.includes('mime_type=video') || lower.includes('video/mp4') || lower.includes('video_mp4') || lower.includes('/video/')) return 'video';
        if (type === 'img' || lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.png') || lower.includes('.webp') || lower.includes('mime=image') || lower.includes('image/jpeg') || lower.includes('image/webp')) return 'image';
        return null;
      }
      try {
        document.querySelectorAll('video').forEach(function(v) {
          try { v.muted = true; v.setAttribute('playsinline', ''); v.playsInline = true; const p = v.play(); if (p && p.catch) p.catch(function() {}); } catch (e) {}
          [v.currentSrc, v.src, v.poster].forEach(function(u) { if (u) push(classify(u, 'video') || 'video', u, v.videoWidth || null, v.videoHeight || null); });
          v.querySelectorAll('source').forEach(function(s) { if (s.src) push(classify(s.src, 'video') || 'video', s.src, null, null); });
        });
        document.querySelectorAll('button,[role="button"],a').forEach(function(el) {
          try { const label = ((el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '')).toLowerCase(); if (label.includes('play') || label.includes('watch') || label.includes('view') || label.includes('open')) el.click(); } catch (e) {}
        });
        window.scrollBy(0, Math.max(120, Math.floor(window.innerHeight * 0.35)));
      } catch (e) {}
      document.querySelectorAll('img').forEach(function(img) { const u = img.currentSrc || img.src; if (u && img.naturalWidth > 240) push('image', u, img.naturalWidth, img.naturalHeight); });
      document.querySelectorAll('source,a,meta[property="og:video"],meta[property="og:video:url"],meta[property="og:image"],meta[name="twitter:player:stream"],meta[name="twitter:image"]').forEach(function(el) {
        const u = el.src || el.href || el.content || el.getAttribute('content') || '';
        const kind = classify(u, '');
        if (kind) push(kind, u, null, null);
      });
      try { performance.getEntriesByType('resource').forEach(function(entry) { const kind = classify(entry.name || '', entry.initiatorType || ''); if (kind) push(kind, entry.name, null, null); }); } catch (e) {}
      const canonical = document.querySelector('link[rel="canonical"]');
      const videoCount = runtime.filter(function(x){ return x.kind === 'video'; }).length;
      const imageCount = runtime.filter(function(x){ return x.kind === 'image'; }).length;
      return JSON.stringify({html: document.documentElement ? document.documentElement.outerHTML : '', pageUrl: location.href, canonicalUrl: canonical ? canonical.href : location.href, runtimeMedia: runtime, videoCount: videoCount, imageCount: imageCount, hasVideo: videoCount > 0 || !!document.querySelector('video'), captureMode: 'field'});
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 44), () {
      if (_done) return;
      if (_lastSource != null && _lastSource!.isNotEmpty) {
        _finish(_lastSource!);
      } else {
        _fail(StateError('Field capture timed out before the page exposed media.'));
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _capture({bool finalAttempt = false}) async {
    if (_done || _controller == null) return;
    try {
      final raw = await _controller!.evaluateJavascript(source: _js);
      if (raw is! String || raw.isEmpty || raw == 'null') return;
      final source = raw.startsWith('"') ? _unquote(raw) : raw;
      _lastSource = source;
      if (_hasRealMedia(source) || finalAttempt) _finish(source);
    } catch (error) {
      if (finalAttempt) _fail(error);
    }
  }

  bool _hasRealMedia(String source) {
    final lower = source.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('"kind":"video"') ||
        lower.contains('mime=video') ||
        lower.contains('mime_type=video') ||
        lower.contains('video/mp4') ||
        lower.contains('video_mp4') ||
        (!lower.contains('"hasvideo":true') && lower.contains('"kind":"image"'));
  }

  void _finish(String source) {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    widget.onComplete(source);
  }

  void _fail(Object error) {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    widget.onFailed(error);
  }

  String _unquote(String raw) {
    if (raw.length < 2) return raw;
    return raw.substring(1, raw.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        cacheEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onWebViewCreated: (controller) => _controller = controller,
      onProgressChanged: (_, progress) {
        if (progress > 35 && !_done) unawaited(_capture());
      },
      onLoadStop: (_, __) async {
        for (var i = 0; i < 36 && !_done; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 650));
          await _capture(finalAttempt: i == 35);
        }
      },
    );
  }
}
