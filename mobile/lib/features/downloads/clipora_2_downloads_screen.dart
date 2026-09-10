import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
      unawaited(_readSharedUrl());
      unawaited(_readClipboard());
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
    _doneBurstTimer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) setState(() => _showDoneBurst = false);
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
          Positioned.fill(child: CustomPaint(painter: const _Clipora2BackgroundPainter())),
          Positioned.fill(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _TopBar(hasBackend: hasBackend),
                const SizedBox(height: 14),
                _HeroCommandCard(
                  controller: controller,
                  urls: urls,
                  matches: matches,
                  clipboardUrl: clipboardUrl,
                  hasBackend: hasBackend,
                  busy: app.busy,
                  onChanged: () => setState(() {}),
                  onPaste: _readClipboard,
                  onClear: () => setState(controller.clear),
                  onSave: _save,
                ),
                const SizedBox(height: 14),
                if (app.status != null) ...[
                  _LiveJobCard(status: app.status!, busy: app.busy, activeJobs: app.activeJobs, hasErrors: app.lastRunHadErrors),
                  const SizedBox(height: 14),
                ],
                _EngineRouteCard(hasBackend: hasBackend),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _PlatformGrid(matches: matches, hasBackend: hasBackend),
                ],
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _RecentRail(recent: recent),
                ],
                const SizedBox(height: 18),
                const _TrustCard(),
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
          if (_showDoneBurst) const Positioned.fill(child: IgnorePointer(child: _DoneBurst())),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ThreadVaultMark(size: 38, showGlow: false),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clipora 2.0', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -.6)),
              Text('Smart Save Command Center', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        ),
        _ModeBadge(label: hasBackend ? 'Resolver Boost' : 'Field Mode', icon: hasBackend ? Icons.cloud_done_rounded : Icons.phone_android_rounded),
      ],
    );
  }
}

class _HeroCommandCard extends StatelessWidget {
  const _HeroCommandCard({
    required this.controller,
    required this.urls,
    required this.matches,
    required this.clipboardUrl,
    required this.hasBackend,
    required this.busy,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onSave,
  });

  final TextEditingController controller;
  final List<String> urls;
  final List<PlatformMatch> matches;
  final String? clipboardUrl;
  final bool hasBackend;
  final bool busy;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10182F), Color(0xFF07111F), Color(0xFF090A14)],
        ),
        border: Border.all(color: Colors.white.withOpacity(.10)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00F2EA).withOpacity(.11), blurRadius: 34, offset: const Offset(0, 18)),
          BoxShadow(color: Colors.black.withOpacity(.28), blurRadius: 18, offset: const Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            const Positioned(right: -36, top: -42, child: _GlowOrb(size: 150, color: Color(0xFF00F2EA))),
            Positioned(left: -44, bottom: -50, child: _GlowOrb(size: 150, color: const Color(0xFFFF4D8D).withOpacity(.70))),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Drop a link. Clipora handles the rest.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -.45, height: 1.08)),
                            SizedBox(height: 6),
                            Text('Autopilot routing for videos, photo carousels, stories, and multi-item posts.', style: TextStyle(color: Colors.white60, height: 1.35, fontSize: 12.8)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ScoreRing(score: urls.isEmpty ? 0 : math.min(20, urls.length), label: urls.isEmpty ? 'Ready' : '${urls.length}'),
                    ],
                  ),
                  const SizedBox(height: 18),
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
                      Expanded(child: _MiniSignal(icon: Icons.bolt_rounded, label: hasBackend ? 'Cloud resolver first' : 'Phone capture first')),
                      const SizedBox(width: 8),
                      Expanded(child: _MiniSignal(icon: Icons.layers_rounded, label: 'Up to 20 items')),
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
                            ? 'Save ${urls.length} links'
                            : 'Smart Save',
                  ),
                  if (clipboardUrl != null && !controller.text.contains(clipboardUrl!)) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: onPaste,
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('Paste link from clipboard'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveJobCard extends StatefulWidget {
  const _LiveJobCard({required this.status, required this.busy, required this.activeJobs, required this.hasErrors});
  final String status;
  final bool busy;
  final int activeJobs;
  final bool hasErrors;

  @override
  State<_LiveJobCard> createState() => _LiveJobCardState();
}

class _LiveJobCardState extends State<_LiveJobCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.busy) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LiveJobCard oldWidget) {
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
    final color = widget.hasErrors ? const Color(0xFFFCA5A5) : const Color(0xFF67E8F9);
    final icon = widget.busy ? Icons.downloading_rounded : widget.hasErrors ? Icons.error_outline_rounded : Icons.check_circle_rounded;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final opacity = widget.busy ? .08 + (_pulse.value * .08) : .08;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withOpacity(.22)),
            color: color.withOpacity(opacity),
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.status, style: const TextStyle(color: Colors.white70, height: 1.35, fontWeight: FontWeight.w650))),
              ],
            ),
            if (widget.busy) ...[
              const SizedBox(height: 12),
              const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(999)), child: LinearProgressIndicator(minHeight: 6)),
              const SizedBox(height: 8),
              Text(
                widget.activeJobs > 1 ? '${widget.activeJobs} saves running — keep adding links.' : 'Saving quietly in the background.',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EngineRouteCard extends StatelessWidget {
  const _EngineRouteCard({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: Color(0xFF8BE9E0)),
              const SizedBox(width: 9),
              const Expanded(child: Text('Clipora 2.0 routing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
              _ModeBadge(label: hasBackend ? 'Boost On' : 'Offline Ready', icon: hasBackend ? Icons.cloud_sync_rounded : Icons.shield_rounded),
            ],
          ),
          const SizedBox(height: 14),
          _RouteStep(n: '1', title: 'Detect', body: 'Reads the platform and chooses the safest supported path.'),
          _RouteStep(n: '2', title: hasBackend ? 'Resolve' : 'Capture', body: hasBackend ? 'Optional resolver handles yt-dlp style extraction, server cache, and hard CDN cases.' : 'Field Mode uses this phone for private-safe capture without a PC server.'),
          const _RouteStep(n: '3', title: 'Save', body: 'Validates real media bytes, saves to Gallery, clears the box, and notifies you.'),
        ],
      ),
    );
  }
}

class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid({required this.matches, required this.hasBackend});
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
                ? 'threads path'
                : match.usesCaptureFallback
                    ? 'hybrid'
                    : 'boost';
        return CliporaPill(icon: match.icon, label: match.label, value: value, color: match.accent);
      }).toList(growable: false),
    );
  }
}

class _RecentRail extends StatelessWidget {
  const _RecentRail({required this.recent});
  final List<DownloadRecord> recent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent saves', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = recent[index];
              final success = item.status == DownloadStatus.completed;
              return Container(
                width: 210,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(.08)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        color: (success ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withOpacity(.12),
                      ),
                      child: Icon(
                        item.kind == MediaKind.video ? Icons.play_circle_outline_rounded : Icons.image_outlined,
                        color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                          const SizedBox(height: 4),
                          Text(success ? 'Saved' : 'Failed', style: TextStyle(fontSize: 12, color: success ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard();

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Built for selling', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'No watermark-removal feature, no password collection, and Threads stays on Clipora’s existing local smart-capture path. Non-Threads media uses the new 2.0 universal route.',
            style: TextStyle(color: Colors.white60, height: 1.38, fontSize: 12.8),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(.06),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8BE9E0)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _MiniSignal extends StatelessWidget {
  const _MiniSignal({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8BE9E0)),
          const SizedBox(width: 7),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w750, color: Colors.white70))),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.label});
  final int score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final pct = score == 0 ? .0 : math.min(1.0, score / 20);
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: pct, strokeWidth: 6, backgroundColor: Colors.white.withOpacity(.08)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              Text(score == 0 ? 'idle' : 'links', style: const TextStyle(fontSize: 9.5, color: Colors.white54, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF00F2EA), Color(0xFF60A5FA)]),
              boxShadow: [BoxShadow(color: const Color(0xFF00F2EA).withOpacity(.18), blurRadius: 16)],
            ),
            child: Text(n, style: const TextStyle(color: Color(0xFF06111C), fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w850)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: Colors.white54, height: 1.32, fontSize: 12.4)),
            ]),
          ),
        ],
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
        tween: Tween(begin: .72, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0), child: Transform.scale(scale: value, child: child)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: const Color(0xFF0B1227).withOpacity(.96),
            border: Border.all(color: const Color(0xFF86EFAC).withOpacity(.25)),
            boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withOpacity(.16), blurRadius: 35)],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 46),
              SizedBox(height: 9),
              Text('Saved to Gallery', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              SizedBox(height: 4),
              Text('Clipora is ready for the next link', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(.22)),
    );
  }
}

class _Clipora2BackgroundPainter extends CustomPainter {
  const _Clipora2BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x2200F2EA), Color(0x0000F2EA), Color(0x18FF0050)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);

    final grid = Paint()
      ..color = Colors.white.withOpacity(.018)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      function classifyResource(u, initiator) {
        const lower = (u || '').toLowerCase();
        const type = (initiator || '').toLowerCase();
        if (!lower || lower.indexOf('http') !== 0) return null;
        if (type === 'video' || lower.includes('.mp4') || lower.includes('mime=video') || lower.includes('mime_type=video') || lower.includes('video/mp4') || lower.includes('video_mp4') || lower.includes('/video/')) return 'video';
        if (type === 'img' || lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.png') || lower.includes('.webp') || lower.includes('mime=image') || lower.includes('image/jpeg') || lower.includes('image/webp')) return 'image';
        return null;
      }
      function wakePage() {
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
      wakePage();
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
