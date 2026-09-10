import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  String? clipboardUrl;
  String? errorText;
  String? lastAutoFingerprint;
  _InstantStage stage = _InstantStage.idle;
  Timer? autoTimer;
  Timer? doneTimer;
  bool showDone = false;

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
    if (autoStart) {
      unawaited(_downloadNow(force: true, returnAfterHandoff: true));
    }
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

  Future<void> _downloadNow({bool force = false, bool returnAfterHandoff = false}) async {
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

    await PlatformServices.startDownloadService(
      message: 'Clipora accepted the link. You can keep watching; saving continues in the background.',
    );

    if (returnAfterHandoff) {
      Future<void>.delayed(const Duration(milliseconds: 240), () async {
        await PlatformServices.returnToSourceApp();
      });
    }

    try {
      final ok = await context.read<AppState>().resolveAndDownload(
        urls,
        sourceLoader: (_) async => throw StateError('On-device page capture is disabled. Clipora Instant uses the resolver engine only.'),
      );
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
              _ShareFirstPanel(
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
              _RoutePanel(hasBackend: hasBackend),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                _RecentPanel(recent: recent),
              ],
              const SizedBox(height: 18),
              const _BoundaryNote(),
            ],
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
          Text('Share. Return. Saved.', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      ),
      _ModeBadge(hasBackend: hasBackend),
    ]);
  }
}

class _ShareFirstPanel extends StatelessWidget {
  const _ShareFirstPanel({
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
              const Text('Share a link to Clipora.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.9, height: 1.05)),
              const SizedBox(height: 8),
              Text(
                hasBackend
                    ? 'Clipora accepts the share, starts the resolver, then returns you to the app you were watching in about a quarter second.'
                    : 'Add a hosted resolver once. After that, sharing any supported link becomes one-tap automatic.',
                style: const TextStyle(color: Colors.white60, height: 1.35, fontSize: 13.2),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          _MetricTile(value: urlCount == 0 ? '0.2s' : '$urlCount', label: urlCount == 1 ? 'link' : 'links'),
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
            hintText: 'Paste or share TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, or Threads…',
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
                      value: hasBackend ? 'auto' : 'needs resolver',
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
                ? 'Downloading in background…'
                : urlCount > 1
                    ? 'Download $urlCount links now'
                    : 'Download now'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Fastest flow: tap Share in the social app → Clipora → you are sent back while the download notification continues.',
          style: TextStyle(color: Colors.white.withOpacity(.52), height: 1.35, fontSize: 12.3, fontWeight: FontWeight.w600),
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
    final icon = failed ? Icons.error_outline_rounded : done ? Icons.check_circle_rounded : busy ? Icons.downloading_rounded : Icons.ios_share_rounded;
    final message = error ?? status ?? 'Share a link to Clipora and it starts automatically.';
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
          const Text('No screen watching needed. Clipora is resolving through the backend and saving quietly.', style: TextStyle(color: Colors.white54, fontSize: 12.5)),
        ],
      ]),
    );
  }
}

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        const Expanded(child: _RouteStep(icon: Icons.ios_share_rounded, title: 'Share', body: '0 taps')),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        Expanded(child: _RouteStep(icon: hasBackend ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded, title: 'Resolve', body: hasBackend ? 'server' : 'needed')),
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
      Text(body, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
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
        'Clipora Instant saves public/shareable media and media you are authorized to access. No watermark-removal tool, no password collection, no private-access bypass, and no in-app social page capture.',
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
        Icon(hasBackend ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 14, color: const Color(0xFF8BE9E0)),
        const SizedBox(width: 6),
        Text(hasBackend ? 'Auto' : 'Connect', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
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
