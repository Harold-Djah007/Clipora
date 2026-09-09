import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../models/media_models.dart';
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
  String? clipboardUrl;

  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readClipboard();
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
    final urls = _extractUrls(controller.text);
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a link first.')),
      );
      return;
    }

    await context.read<AppState>().resolveAndDownload(
      urls,
      sourceLoader: (url) async {
        final source = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => _CapturePage(url: url), fullscreenDialog: true),
        );
        if (source == null || source.isEmpty) {
          throw StateError('Capture was cancelled before media was found.');
        }
        return source;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final urls = _extractUrls(controller.text);
    final matches = UniversalPlatformDetector.detectAll(urls);
    final recent = app.history.take(3).toList();

    return CliporaPage(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          CliporaSectionTitle(
            title: 'Save',
            subtitle: 'Paste any supported social link. Clipora uses the universal backend first, then private-safe Threads capture when needed.',
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
                      ? 'Supported: ${UniversalPlatformDetector.supportedLabel}. Keep the backend open for non-Threads links.'
                      : '${urls.length} link${urls.length == 1 ? '' : 's'} ready',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
                ),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: matches.map(_platformPill).toList(growable: false),
                  ),
                ],
                const SizedBox(height: 14),
                CliporaPrimaryButton(
                  onPressed: app.busy ? null : _save,
                  icon: Icon(app.busy ? Icons.hourglass_top_rounded : Icons.download_rounded, color: app.busy ? Colors.white54 : const Color(0xFF041216)),
                  label: app.busy ? 'Saving…' : urls.length > 1 ? 'Save ${urls.length} links' : 'Save media',
                ),
              ],
            ),
          ),
          if (app.status != null) ...[
            const SizedBox(height: 12),
            PremiumCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    app.busy
                        ? Icons.sync_rounded
                        : app.lastRunHadErrors
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                    color: app.lastRunHadErrors ? const Color(0xFFF0A8A8) : const Color(0xFF8BE9E0),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(app.status!, style: const TextStyle(height: 1.4, color: Colors.white70))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('How it works', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          const PremiumCard(
            child: Column(
              children: [
                _Step(n: '1', text: 'Copy a social media post, video, reel, short, pin, or public story link.'),
                _Step(n: '2', text: 'Clipora detects the platform and calls the universal backend for direct media.'),
                _Step(n: '3', text: 'Threads/private-safe flows use local capture so Clipora never asks for your password.'),
                _Step(n: '4', text: 'The file is validated, saved, and published to your Gallery.'),
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
    );
  }

  Widget _platformPill(PlatformMatch match) {
    return CliporaPill(
      icon: match.icon,
      label: match.label,
      value: match.isThreads ? 'capture' : match.preferBackend ? 'backend' : 'check',
      color: match.accent,
    );
  }
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

class _CapturePage extends StatefulWidget {
  final String url;
  const _CapturePage({required this.url});

  @override
  State<_CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<_CapturePage> {
  InAppWebViewController? _controller;
  String _status = 'Opening post';
  bool _done = false;

  static const _js = r'''
    (function() {
      function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return u; } }
      const runtime = [];
      document.querySelectorAll('video').forEach(function(v) {
        const u = v.currentSrc || v.src;
        if (u) runtime.push({kind:'video', url: abs(u), width: v.videoWidth || null, height: v.videoHeight || null});
      });
      document.querySelectorAll('img').forEach(function(img) {
        const u = img.currentSrc || img.src;
        if (u && img.naturalWidth > 240) runtime.push({kind:'image', url: abs(u), width: img.naturalWidth, height: img.naturalHeight});
      });
      const canonical = document.querySelector('link[rel="canonical"]');
      return JSON.stringify({
        html: document.documentElement ? document.documentElement.outerHTML : '',
        pageUrl: location.href,
        canonicalUrl: canonical ? canonical.href : location.href,
        runtimeMedia: runtime,
        hasVideo: runtime.some(function(x){ return x.kind === 'video'; }) || !!document.querySelector('video'),
        captureMode: 'auto'
      });
    })();
  ''';

  Future<void> _capture({bool force = false}) async {
    if (_done || _controller == null) return;
    try {
      final raw = await _controller!.evaluateJavascript(source: _js);
      if (raw is! String || raw.isEmpty || raw == 'null') return;
      final source = raw.startsWith('"') ? _unquote(raw) : raw;
      final ready = source.contains('.mp4') || source.contains('cdninstagram') || source.contains('fbcdn');
      if (ready || force) {
        _done = true;
        if (mounted) Navigator.pop(context, source);
      }
    } catch (_) {}
  }

  String _unquote(String raw) {
    if (raw.length < 2) return raw;
    return raw.substring(1, raw.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      appBar: AppBar(
        title: Text(_status, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => _capture(force: true), child: const Text('Capture')),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
          cacheEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
        ),
        onWebViewCreated: (c) => _controller = c,
        onLoadStop: (_, __) async {
          if (!mounted) return;
          setState(() => _status = 'Reading media');
          for (var i = 0; i < 12 && !_done; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 700));
            await _capture();
          }
        },
      ),
    );
  }
}
