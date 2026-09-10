import 'dart:async';
import 'dart:convert';

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

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with WidgetsBindingObserver {
  final controller = TextEditingController();
  final List<_CaptureRequest> _captureQueue = [];
  String? clipboardUrl;
  _CaptureRequest? _activeCapture;
  int _captureSeq = 0;
  bool _showDoneBurst = false;
  Timer? _doneBurstTimer;

  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _readSharedUrl();
      await _readClipboard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doneBurstTimer?.cancel();
    final pending = [if (_activeCapture != null) _activeCapture!, ..._captureQueue];
    for (final request in pending) {
      request.timeout?.cancel();
      if (!request.completer.isCompleted) {
        request.completer.completeError(StateError('Clipora closed before background capture finished.'));
      }
    }
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readSharedUrl();
      _readClipboard();
    }
  }

  List<String> _extractUrls(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final match in _urlPattern.allMatches(raw)) {
      final value = match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
      if (seen.add(value)) out.add(value);
    }
    return out;
  }

  Future<void> _readSharedUrl() async {
    final shared = await PlatformServices.takeSharedUrl();
    if (!mounted || shared == null) return;
    final urls = _extractUrls(shared);
    if (urls.isEmpty) return;
    setState(() {
      controller.text = urls.join('\n');
      clipboardUrl = urls.first;
    });
  }

  Future<void> _readClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final urls = _extractUrls(data?.text ?? '');
    if (!mounted) return;
    setState(() {
      clipboardUrl = urls.isEmpty ? null : urls.first;
      if (controller.text.trim().isEmpty && urls.isNotEmpty) {
        controller.text = urls.join('\n');
      }
    });
  }

  Future<void> _save() async {
    final submittedText = controller.text;
    final urls = _extractUrls(submittedText);
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a link first.')),
      );
      return;
    }

    final ok = await context.read<AppState>().resolveAndDownload(
      urls,
      sourceLoader: _captureInBackground,
    );

    if (!mounted) return;
    if (ok) {
      setState(() {
        if (controller.text == submittedText) {
          controller.clear();
          clipboardUrl = null;
        }
      });
      _flashDoneBurst();
    }
  }

  Future<String> _captureInBackground(String url) {
    final request = _CaptureRequest(
      id: _captureSeq++,
      url: url,
      completer: Completer<String>(),
    );
    request.timeout = Timer(const Duration(seconds: 46), () {
      _completeCapture(
        request,
        error: StateError('Field capture timed out before the page exposed real media. Open the post once in Access, let it play, then retry.'),
      );
    });
    _captureQueue.add(request);
    _pumpCaptureQueue();
    return request.completer.future;
  }

  void _pumpCaptureQueue() {
    if (!mounted || _activeCapture != null || _captureQueue.isEmpty) return;
    setState(() => _activeCapture = _captureQueue.removeAt(0));
  }

  void _completeCapture(_CaptureRequest request, {String? source, Object? error}) {
    request.timeout?.cancel();
    _captureQueue.remove(request);
    if (_activeCapture != request) return;

    if (!request.completer.isCompleted) {
      if (source != null && source.isNotEmpty) {
        request.completer.complete(source);
      } else {
        request.completer.completeError(error ?? StateError('Field capture ended before media was found.'));
      }
    }

    if (!mounted) return;
    setState(() => _activeCapture = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpCaptureQueue());
  }

  void _completeActiveCapture({String? source, Object? error}) {
    final request = _activeCapture;
    if (request == null) return;
    _completeCapture(request, source: source, error: error);
  }

  void _flashDoneBurst() {
    _doneBurstTimer?.cancel();
    setState(() => _showDoneBurst = true);
    _doneBurstTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showDoneBurst = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final urls = _extractUrls(controller.text);
    final matches = UniversalPlatformDetector.detectAll(urls);
    final recent = app.history.take(3).toList();
    final hasBackend = app.universalResolver.hasConfiguredBackend;

    return CliporaPage(
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                CliporaSectionTitle(
                  title: 'Save',
                  subtitle: 'Paste any supported social link. Field Mode captures on this phone and saves to Gallery.',
                  trailing: const ThreadVaultMark(size: 36, showGlow: false),
                ),
                const SizedBox(height: 20),
                if (clipboardUrl != null && !controller.text.contains(clipboardUrl!)) ...[
                  PremiumCard(
                    child: Row(children: [
                      const Icon(Icons.content_paste_rounded, size: 18, color: Color(0xFF8BE9E0)),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('A link is on your clipboard', style: TextStyle(fontWeight: FontWeight.w700))),
                      TextButton(
                        onPressed: () => setState(() => controller.text = clipboardUrl!),
                        child: const Text('Paste'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                PremiumCard(
                  glow: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        minLines: 3,
                        maxLines: 5,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, Threads…',
                          prefixIcon: const Icon(Icons.link_rounded),
                          suffixIcon: controller.text.isEmpty
                              ? IconButton(
                                  tooltip: 'Paste',
                                  onPressed: _readClipboard,
                                  icon: const Icon(Icons.content_paste_go_rounded),
                                )
                              : IconButton(
                                  tooltip: 'Clear',
                                  onPressed: () => setState(() => controller.clear()),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        urls.isEmpty
                            ? 'Supported: ${UniversalPlatformDetector.supportedLabel}. You can add another link while a save is already running.'
                            : '${urls.length} link${urls.length == 1 ? '' : 's'} ready',
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
                      ),
                      if (matches.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: matches.map((match) => _platformPill(match, hasBackend)).toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 14),
                      CliporaPrimaryButton(
                        onPressed: _save,
                        icon: Icon(app.busy ? Icons.add_circle_outline_rounded : Icons.download_rounded, color: const Color(0xFF041216)),
                        label: app.busy
                            ? 'Add another save'
                            : urls.length > 1
                                ? 'Save ${urls.length} links'
                                : 'Save media',
                      ),
                    ],
                  ),
                ),
                if (app.status != null) ...[
                  const SizedBox(height: 12),
                  _DownloadStatusCard(
                    status: app.status!,
                    busy: app.busy,
                    activeJobs: app.activeJobs,
                    hasErrors: app.lastRunHadErrors,
                  ),
                ],
                const SizedBox(height: 20),
                const Text('How it works', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                PremiumCard(
                  child: Column(
                    children: [
                      const _Step(n: '1', text: 'Copy a social link, or share the post to Clipora from TikTok, X, YouTube, and the rest.'),
                      _Step(
                        n: '2',
                        text: hasBackend
                            ? 'Clipora tries your optional resolver first, then falls back to Field Mode capture on this phone.'
                            : 'Clipora runs in Field Mode: it detects the platform and captures media on this phone without a PC/server.',
                      ),
                      const _Step(n: '3', text: 'The hidden capture viewport watches videos, images, and page network resources so carousels can keep every real item it sees.'),
                      const _Step(n: '4', text: 'The file is validated, saved to Gallery, the link box clears, and Clipora notifies you when finished.'),
                    ],
                  ),
                ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Recent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  ...recent.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PremiumCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Icon(item.kind == MediaKind.video ? Icons.play_circle_outline_rounded : Icons.image_outlined, color: const Color(0xFF8BE9E0)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(item.status == DownloadStatus.completed ? 'Saved' : 'Failed', style: TextStyle(fontSize: 12, color: item.status == DownloadStatus.completed ? const Color(0xFF86EFAC) : const Color(0xFFF0A8A8))),
                          ]),
                        ),
                      )),
                ],
              ],
            ),
          ),
          if (_activeCapture != null)
            Positioned(
              left: 0,
              top: 0,
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height * .78,
              child: Opacity(
                opacity: 0.01,
                child: IgnorePointer(
                  child: _HiddenCaptureHost(
                    key: ValueKey(_activeCapture!.id),
                    url: _activeCapture!.url,
                    onComplete: (source) => _completeActiveCapture(source: source),
                    onFailed: (error) => _completeActiveCapture(error: error),
                  ),
                ),
              ),
            ),
          if (_showDoneBurst)
            const Positioned.fill(
              child: IgnorePointer(child: _DoneBurst()),
            ),
        ],
      ),
    );
  }

  Widget _platformPill(PlatformMatch match, bool hasBackend) {
    final value = !hasBackend
        ? 'field mode'
        : match.isThreads
            ? 'field mode'
            : match.usesCaptureFallback
                ? 'resolver+field'
                : match.preferBackend
                    ? 'resolver boost'
                    : 'field mode';

    return CliporaPill(
      icon: match.icon,
      label: match.label,
      value: value,
      color: match.accent,
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

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.35))),
      ]),
    );
  }
}

class _DownloadStatusCard extends StatefulWidget {
  const _DownloadStatusCard({
    required this.status,
    required this.busy,
    required this.activeJobs,
    required this.hasErrors,
  });

  final String status;
  final bool busy;
  final int activeJobs;
  final bool hasErrors;

  @override
  State<_DownloadStatusCard> createState() => _DownloadStatusCardState();
}

class _DownloadStatusCardState extends State<_DownloadStatusCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _DownloadStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.busy && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.busy
        ? Icons.downloading_rounded
        : widget.hasErrors
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded;
    final color = widget.hasErrors ? const Color(0xFFF0A8A8) : const Color(0xFF8BE9E0);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final scale = widget.busy ? 1 + (_pulse.value * .04) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: PremiumCard(
        glow: widget.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.status, style: const TextStyle(height: 1.4, color: Colors.white70))),
              ],
            ),
            if (widget.busy) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 6),
              ),
              const SizedBox(height: 8),
              Text(
                widget.activeJobs > 1 ? '${widget.activeJobs} saves running. You can paste another link.' : 'Saving in the background. You can paste another link.',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DoneBurst extends StatelessWidget {
  const _DoneBurst();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .7, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(scale: value, child: child),
        ),
        child: PremiumCard(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 42),
              SizedBox(height: 8),
              Text('Saved to Gallery', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              SizedBox(height: 4),
              Text('Ready for the next link', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HiddenCaptureHost extends StatefulWidget {
  const _HiddenCaptureHost({
    super.key,
    required this.url,
    required this.onComplete,
    required this.onFailed,
  });

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
      function classifyResource(u, initiator) {
        const lower = (u || '').toLowerCase();
        const type = (initiator || '').toLowerCase();
        if (!lower || lower.indexOf('http') !== 0) return null;
        if (type === 'video' || lower.includes('.mp4') || lower.includes('mime=video') || lower.includes('mime_type=video') || lower.includes('video/mp4') || lower.includes('video_mp4') || lower.includes('/video/')) return 'video';
        if (type === 'img' || lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.png') || lower.includes('.webp') || lower.includes('mime=image') || lower.includes('image/jpeg') || lower.includes('image/webp')) return 'image';
        return null;
      }
      function clickPlayable() {
        try {
          document.querySelectorAll('video').forEach(function(v) {
            try {
              v.muted = true;
              v.setAttribute('muted', '');
              v.setAttribute('playsinline', '');
              v.playsInline = true;
              const attempt = v.play();
              if (attempt && attempt.catch) attempt.catch(function() {});
            } catch (e) {}
          });
          document.querySelectorAll('button,[role="button"],a').forEach(function(el) {
            try {
              const label = ((el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '')).toLowerCase();
              if (label.includes('play') || label.includes('watch') || label.includes('view') || label.includes('open')) el.click();
            } catch (e) {}
          });
          window.scrollBy(0, Math.max(120, Math.floor(window.innerHeight * 0.35)));
        } catch (e) {}
      }
      clickPlayable();
      document.querySelectorAll('video').forEach(function(v) {
        const urls = [v.currentSrc, v.src, v.poster];
        v.querySelectorAll('source').forEach(function(s) { urls.push(s.src); });
        urls.forEach(function(u) {
          if (!u) return;
          const kind = classifyResource(u, 'video') || (String(u).toLowerCase().match(/\.(jpe?g|png|webp)/) ? 'image' : 'video');
          push(kind, u, v.videoWidth || null, v.videoHeight || null);
        });
      });
      document.querySelectorAll('img').forEach(function(img) {
        const u = img.currentSrc || img.src;
        if (u && img.naturalWidth > 240) push('image', u, img.naturalWidth, img.naturalHeight);
      });
      document.querySelectorAll('source,a,meta[property="og:video"],meta[property="og:video:url"],meta[property="og:image"],meta[name="twitter:player:stream"],meta[name="twitter:image"]').forEach(function(el) {
        const u = el.src || el.href || el.content || el.getAttribute('content') || '';
        const kind = classifyResource(u, '');
        if (kind) push(kind, u, null, null);
      });
      try {
        performance.getEntriesByType('resource').forEach(function(entry) {
          const kind = classifyResource(entry.name || '', entry.initiatorType || '');
          if (kind) push(kind, entry.name, null, null);
        });
      } catch (e) {}
      const canonical = document.querySelector('link[rel="canonical"]');
      const videoCount = runtime.filter(function(x){ return x.kind === 'video'; }).length;
      const imageCount = runtime.filter(function(x){ return x.kind === 'image'; }).length;
      return JSON.stringify({
        html: document.documentElement ? document.documentElement.outerHTML : '',
        pageUrl: location.href,
        canonicalUrl: canonical ? canonical.href : location.href,
        runtimeMedia: runtime,
        videoCount: videoCount,
        imageCount: imageCount,
        hasVideo: videoCount > 0 || !!document.querySelector('video'),
        captureMode: 'field'
      });
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
      final ready = _hasConfirmedRuntimeMedia(source);
      if (ready || finalAttempt) _finish(source);
    } catch (error) {
      if (finalAttempt) _fail(error);
    }
  }

  bool _hasConfirmedRuntimeMedia(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        final hasVideoElement = decoded['hasVideo'] == true;
        final runtime = decoded['runtimeMedia'];
        var videoCount = 0;
        var imageCount = 0;
        if (runtime is List) {
          for (final item in runtime) {
            if (item is! Map) continue;
            final kind = '${item['kind'] ?? ''}'.toLowerCase();
            final url = '${item['url'] ?? ''}';
            if (kind == 'video' && _looksLikeRuntimeVideo(url)) {
              videoCount++;
            } else if (kind == 'image' && _looksLikeRuntimeImage(url)) {
              imageCount++;
            }
          }
        }
        if (videoCount > 0) return true;
        if (!hasVideoElement && imageCount > 0) return true;
        return false;
      }
    } catch (_) {}

    final lower = source.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('"kind":"video"') ||
        lower.contains('mime=video') ||
        lower.contains('mime_type=video') ||
        lower.contains('video/mp4') ||
        lower.contains('video_mp4');
  }

  bool _looksLikeRuntimeVideo(String url) {
    final lower = url.toLowerCase();
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final snapCandidate = host.endsWith('sc-cdn.net') &&
        (lower.contains('/media/') || lower.contains('/video/') || lower.contains('video') || lower.contains('mime=video'));
    return lower.startsWith('http') &&
        !lower.contains('.m3u8') &&
        !lower.contains('mpegurl') &&
        !lower.contains('mime=audio') &&
        (lower.contains('.mp4') ||
            lower.contains('mime=video') ||
            lower.contains('mime_type=video') ||
            lower.contains('video/mp4') ||
            lower.contains('video_mp4') ||
            lower.contains('format=mp4') ||
            snapCandidate);
  }

  bool _looksLikeRuntimeImage(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') &&
        (lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.png') ||
            lower.contains('.webp') ||
            lower.contains('mime=image') ||
            lower.contains('image/jpeg') ||
            lower.contains('image/webp') ||
            lower.contains('image/png'));
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
      onWebViewCreated: (c) => _controller = c,
      onProgressChanged: (_, progress) {
        if (progress > 35 && !_done) {
          unawaited(_capture());
        }
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