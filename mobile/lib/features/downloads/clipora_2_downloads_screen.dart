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

class Clipora2DownloadsScreen extends StatefulWidget {
  const Clipora2DownloadsScreen({super.key});

  @override
  State<Clipora2DownloadsScreen> createState() => _Clipora2DownloadsScreenState();
}

class _Clipora2DownloadsScreenState extends State<Clipora2DownloadsScreen> with WidgetsBindingObserver {
  final controller = TextEditingController();
  final List<_CaptureRequest> _queue = [];
  String? clipboardUrl;
  _CaptureRequest? _active;
  int _seq = 0;
  bool _doneBurst = false;
  Timer? _doneTimer;

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
    _doneTimer?.cancel();
    final pending = [if (_active != null) _active!, ..._queue];
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
      unawaited(_readSharedUrl());
      unawaited(_readClipboard());
    }
  }

  List<String> _extractUrls(String raw) {
    final seen = <String>{};
    final urls = <String>[];
    for (final match in _urlPattern.allMatches(raw)) {
      final value = match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
      if (seen.add(value)) urls.add(value);
    }
    return urls;
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
    final submitted = controller.text;
    final urls = _extractUrls(submitted);
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste or share a supported social link first.')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    final ok = await context.read<AppState>().resolveAndDownload(
      urls,
      sourceLoader: _captureInBackground,
    );

    if (!mounted) return;
    if (ok) {
      setState(() {
        if (controller.text == submitted) {
          controller.clear();
          clipboardUrl = null;
        }
      });
      _flashDone();
    }
  }

  Future<String> _captureInBackground(String url) {
    final request = _CaptureRequest(id: _seq++, url: url, completer: Completer<String>());
    request.timeout = Timer(const Duration(seconds: 46), () {
      _completeCapture(request, error: StateError('Field capture timed out before the page exposed real media. Open it once in Access, let it play, then retry.'));
    });
    _queue.add(request);
    _pumpQueue();
    return request.completer.future;
  }

  void _pumpQueue() {
    if (!mounted || _active != null || _queue.isEmpty) return;
    setState(() => _active = _queue.removeAt(0));
  }

  void _completeCapture(_CaptureRequest request, {String? source, Object? error}) {
    request.timeout?.cancel();
    _queue.remove(request);
    if (_active != request) return;
    if (!request.completer.isCompleted) {
      if (source != null && source.isNotEmpty) {
        request.completer.complete(source);
      } else {
        request.completer.completeError(error ?? StateError('Field capture ended before media was found.'));
      }
    }
    if (!mounted) return;
    setState(() => _active = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpQueue());
  }

  void _flashDone() {
    _doneTimer?.cancel();
    setState(() => _doneBurst = true);
    _doneTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _doneBurst = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final urls = _extractUrls(controller.text);
    final matches = UniversalPlatformDetector.detectAll(urls);
    final hasBackend = app.universalResolver.hasConfiguredBackend;
    final recent = app.history.take(4).toList();

    return CliporaPage(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 112),
      child: Stack(
        children: [
          const Positioned.fill(child: _AuraBackground()),
          Positioned.fill(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _Header(hasBackend: hasBackend),
                const SizedBox(height: 14),
                _CommandCard(
                  controller: controller,
                  urls: urls,
                  matches: matches,
                  hasBackend: hasBackend,
                  busy: app.busy,
                  clipboardUrl: clipboardUrl,
                  onChanged: () => setState(() {}),
                  onPaste: _readClipboard,
                  onClear: () => setState(() => controller.clear()),
                  onSave: _save,
                ),
                if (app.status != null) ...[
                  const SizedBox(height: 14),
                  _LiveStatus(status: app.status!, busy: app.busy, activeJobs: app.activeJobs, hasErrors: app.lastRunHadErrors),
                ],
                const SizedBox(height: 14),
                _RouteCard(hasBackend: hasBackend),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _PlatformPills(matches: matches, hasBackend: hasBackend),
                ],
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _RecentSaves(recent: recent),
                ],
                const SizedBox(height: 18),
                const _SafetyCard(),
              ],
            ),
          ),
          if (_active != null)
            Positioned(
              left: 0,
              top: 0,
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height * .78,
              child: Opacity(
                opacity: 0.01,
                child: IgnorePointer(
                  child: _HiddenCaptureHost(
                    key: ValueKey(_active!.id),
                    url: _active!.url,
                    onComplete: (source) => _completeCapture(_active!, source: source),
                    onFailed: (error) => _completeCapture(_active!, error: error),
                  ),
                ),
              ),
            ),
          if (_doneBurst) const Positioned.fill(child: IgnorePointer(child: _DoneOverlay())),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ThreadVaultMark(size: 40, showGlow: false),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clipora 2.0', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.7)),
              Text('Smart Save Command Center', style: TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        _Badge(icon: hasBackend ? Icons.cloud_done_rounded : Icons.phone_android_rounded, text: hasBackend ? 'Boost' : 'Field'),
      ],
    );
  }
}

class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.controller,
    required this.urls,
    required this.matches,
    required this.hasBackend,
    required this.busy,
    required this.clipboardUrl,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onSave,
  });

  final TextEditingController controller;
  final List<String> urls;
  final List<PlatformMatch> matches;
  final bool hasBackend;
  final bool busy;
  final String? clipboardUrl;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10182F), Color(0xFF07111F), Color(0xFF090A14)],
        ),
        border: Border.all(color: Colors.white.withOpacity(.10)),
        boxShadow: [BoxShadow(color: const Color(0xFF00F2EA).withOpacity(.11), blurRadius: 34, offset: const Offset(0, 18))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('One tap. Every real item.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                    SizedBox(height: 6),
                    Text('Built for videos, stories, carousels, and multi-post batches.', style: TextStyle(color: Colors.white60, height: 1.35, fontSize: 12.8)),
                  ],
                ),
              ),
              _CountRing(count: urls.length),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 14.5, height: 1.35),
            decoration: InputDecoration(
              hintText: 'Paste TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, or Threads…',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: controller.text.isEmpty
                  ? IconButton(tooltip: 'Paste', onPressed: onPaste, icon: const Icon(Icons.content_paste_go_rounded))
                  : IconButton(tooltip: 'Clear', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniStat(icon: Icons.route_rounded, text: hasBackend ? 'Resolver first' : 'Phone first')),
              const SizedBox(width: 8),
              const Expanded(child: _MiniStat(icon: Icons.layers_rounded, text: '20 items max')),
            ],
          ),
          const SizedBox(height: 14),
          CliporaPrimaryButton(
            onPressed: onSave,
            height: 56,
            icon: Icon(busy ? Icons.add_circle_outline_rounded : Icons.download_rounded, color: const Color(0xFF031318)),
            label: busy
                ? 'Add another save'
                : urls.length > 1
                    ? 'Smart Save ${urls.length} links'
                    : 'Smart Save',
          ),
          if (clipboardUrl != null && !controller.text.contains(clipboardUrl!)) ...[
            const SizedBox(height: 10),
            TextButton.icon(onPressed: onPaste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Paste link from clipboard')),
          ],
        ],
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.status, required this.busy, required this.activeJobs, required this.hasErrors});
  final String status;
  final bool busy;
  final int activeJobs;
  final bool hasErrors;

  @override
  Widget build(BuildContext context) {
    final color = hasErrors ? const Color(0xFFFCA5A5) : const Color(0xFF67E8F9);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(busy ? Icons.downloading_rounded : hasErrors ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(status, style: const TextStyle(color: Colors.white70, height: 1.35, fontWeight: FontWeight.w700))),
          ]),
          if (busy) ...[
            const SizedBox(height: 12),
            const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 6)),
            const SizedBox(height: 8),
            Text(activeJobs > 1 ? '$activeJobs saves running — paste another link.' : 'Saving quietly in the background.', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8BE9E0)),
            const SizedBox(width: 9),
            const Expanded(child: Text('2.0 downloader route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
            _Badge(icon: hasBackend ? Icons.cloud_sync_rounded : Icons.shield_rounded, text: hasBackend ? 'Hybrid' : 'Local'),
          ]),
          const SizedBox(height: 12),
          _RouteStep(n: '1', title: 'Detect', body: 'Clipora identifies the platform and chooses the best supported route.'),
          _RouteStep(n: '2', title: hasBackend ? 'Resolve' : 'Capture', body: hasBackend ? 'Optional resolver handles extractor, cache, and hard CDN cases.' : 'Field Mode captures on this phone without a PC/server.'),
          const _RouteStep(n: '3', title: 'Save', body: 'Real media bytes are validated, saved to Gallery, and the link box clears.'),
        ],
      ),
    );
  }
}

class _PlatformPills extends StatelessWidget {
  const _PlatformPills({required this.matches, required this.hasBackend});
  final List<PlatformMatch> matches;
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: matches.map((match) {
        final value = !hasBackend
            ? 'field'
            : match.isThreads
                ? 'threads'
                : match.usesCaptureFallback
                    ? 'hybrid'
                    : 'boost';
        return CliporaPill(icon: match.icon, label: match.label, value: value, color: match.accent);
      }).toList(growable: false),
    );
  }
}

class _RecentSaves extends StatelessWidget {
  const _RecentSaves({required this.recent});
  final List<DownloadRecord> recent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent saves', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        ...recent.map((item) {
          final success = item.status == DownloadStatus.completed;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PremiumCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              borderRadius: BorderRadius.circular(20),
              child: Row(children: [
                Icon(item.kind == MediaKind.video ? Icons.play_circle_outline_rounded : Icons.image_outlined, color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                const SizedBox(width: 10),
                Expanded(child: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                Text(success ? 'Saved' : 'Failed', style: TextStyle(fontSize: 12, color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
              ]),
            ),
          );
        }),
      ],
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: const Text(
        'Commercial-safe boundary: no watermark-removal feature, no password collection, and Threads stays on Clipora’s existing local smart-capture path.',
        style: TextStyle(color: Colors.white60, height: 1.38, fontSize: 12.8),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.10))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFF8BE9E0)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: Colors.black.withOpacity(.18), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(.08))),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF8BE9E0)),
        const SizedBox(width: 7),
        Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700, color: Colors.white70))),
      ]),
    );
  }
}

class _CountRing extends StatelessWidget {
  const _CountRing({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final pct = count == 0 ? 0.0 : (count / 20).clamp(0.0, 1.0);
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: pct, strokeWidth: 6, backgroundColor: Colors.white.withOpacity(.08)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(count == 0 ? 'Go' : '$count', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          Text(count == 0 ? 'idle' : 'links', style: const TextStyle(fontSize: 9.5, color: Colors.white54, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

class _RouteStep extends StatelessWidget {
  const _RouteStep({required this.n, required this.title, required this.body});
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 26, height: 26, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF00F2EA), Color(0xFF60A5FA)])), child: Text(n, style: const TextStyle(color: Color(0xFF06111C), fontWeight: FontWeight.w900, fontSize: 12))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body, style: const TextStyle(color: Colors.white54, height: 1.32, fontSize: 12.4)),
        ])),
      ]),
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .72, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0), child: Transform.scale(scale: value, child: child)),
        child: PremiumCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          borderRadius: BorderRadius.circular(28),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 46),
            SizedBox(height: 9),
            Text('Saved to Gallery', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            SizedBox(height: 4),
            Text('Ready for the next link', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
          ]),
        ),
      ),
    );
  }
}

class _AuraBackground extends StatelessWidget {
  const _AuraBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.7, -1),
          radius: 1.2,
          colors: [const Color(0xFF00F2EA).withOpacity(.14), Colors.transparent],
        ),
      ),
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
      function wake() {
        try {
          document.querySelectorAll('video').forEach(function(v) {
            try { v.muted = true; v.setAttribute('playsinline', ''); v.playsInline = true; const p = v.play(); if (p && p.catch) p.catch(function() {}); } catch (e) {}
          });
          document.querySelectorAll('button,[role="button"],a').forEach(function(el) {
            try { const label = ((el.getAttribute('aria-label') || '') + ' ' + (el.textContent || '')).toLowerCase(); if (label.includes('play') || label.includes('watch') || label.includes('view') || label.includes('open')) el.click(); } catch (e) {}
          });
          window.scrollBy(0, Math.max(120, Math.floor(window.innerHeight * 0.35)));
        } catch (e) {}
      }
      wake();
      document.querySelectorAll('video').forEach(function(v) {
        [v.currentSrc, v.src, v.poster].forEach(function(u) { if (u) push(classify(u, 'video') || 'video', u, v.videoWidth || null, v.videoHeight || null); });
        v.querySelectorAll('source').forEach(function(s) { if (s.src) push(classify(s.src, 'video') || 'video', s.src, null, null); });
      });
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
