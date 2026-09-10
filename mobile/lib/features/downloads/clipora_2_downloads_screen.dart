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

enum _StudioStage { paste, analyze, pick, save }

class Clipora2DownloadsScreen extends StatefulWidget {
  const Clipora2DownloadsScreen({super.key});

  @override
  State<Clipora2DownloadsScreen> createState() => _Clipora2DownloadsScreenState();
}

class _Clipora2DownloadsScreenState extends State<Clipora2DownloadsScreen> with WidgetsBindingObserver {
  final controller = TextEditingController();
  final List<_CaptureRequest> _captureQueue = [];
  final Set<String> _selected = <String>{};
  final ScrollController _scrollController = ScrollController();

  String? clipboardUrl;
  String? _error;
  _CaptureRequest? _activeCapture;
  List<ResolvedPost> _plan = const [];
  _StudioStage _stage = _StudioStage.paste;
  int _captureSeq = 0;
  bool _showDone = false;
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
    _scrollController.dispose();
    final pending = [if (_activeCapture != null) _activeCapture!, ..._captureQueue];
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
    return urls.take(20).toList(growable: false);
  }

  Future<void> _readSharedUrl() async {
    final shared = await PlatformServices.takeSharedUrl();
    if (!mounted || shared == null) return;
    final urls = _extractUrls(shared);
    if (urls.isEmpty) return;
    setState(() {
      controller.text = urls.join('\n');
      clipboardUrl = urls.first;
      _stage = _StudioStage.analyze;
      _plan = const [];
      _selected.clear();
      _error = null;
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
        _stage = _StudioStage.analyze;
      }
    });
  }

  void _onInputChanged() {
    setState(() {
      _plan = const [];
      _selected.clear();
      _error = null;
      _stage = _extractUrls(controller.text).isEmpty ? _StudioStage.paste : _StudioStage.analyze;
    });
  }

  Future<void> _analyze() async {
    final urls = _extractUrls(controller.text);
    if (urls.isEmpty) {
      _showSnack('Paste or share a supported social link first.');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _stage = _StudioStage.analyze;
      _plan = const [];
      _selected.clear();
      _error = null;
    });

    try {
      final posts = await context.read<AppState>().scanForMedia(urls, sourceLoader: _captureInBackground);
      if (!mounted) return;
      setState(() {
        _plan = posts;
        _selected.clear();
        for (var p = 0; p < posts.length; p++) {
          for (var m = 0; m < posts[p].media.length; m++) {
            _selected.add(_key(p, m));
          }
        }
        _stage = _StudioStage.pick;
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        ));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(error);
        _stage = _StudioStage.analyze;
      });
    }
  }

  Future<void> _saveSelected() async {
    final selectedPlan = _selectedPlan();
    if (selectedPlan.isEmpty) {
      _showSnack('Select at least one media item to save.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _stage = _StudioStage.save);
    final ok = await context.read<AppState>().saveResolvedMedia(selectedPlan);
    if (!mounted) return;
    if (ok) {
      setState(() {
        controller.clear();
        clipboardUrl = null;
        _plan = const [];
        _selected.clear();
        _stage = _StudioStage.paste;
        _error = null;
      });
      _flashDone();
    } else {
      setState(() => _stage = _StudioStage.pick);
    }
  }

  String _key(int postIndex, int mediaIndex) => '$postIndex:$mediaIndex';

  int get _selectedCount => _selected.length;

  int get _mediaCount => _plan.fold(0, (sum, post) => sum + post.media.length);

  List<ResolvedPost> _selectedPlan() {
    final posts = <ResolvedPost>[];
    for (var p = 0; p < _plan.length; p++) {
      final post = _plan[p];
      final media = <ResolvedMedia>[];
      for (var m = 0; m < post.media.length; m++) {
        if (_selected.contains(_key(p, m))) media.add(post.media[m]);
      }
      if (media.isNotEmpty) {
        posts.add(ResolvedPost(
          sourceUrl: post.sourceUrl,
          postId: post.postId,
          author: post.author,
          caption: post.caption,
          media: media,
        ));
      }
    }
    return posts;
  }

  Future<String> _captureInBackground(String url) {
    final request = _CaptureRequest(id: _captureSeq++, url: url, completer: Completer<String>());
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
    final active = _activeCapture;
    if (active == null) return;
    _completeCapture(active, source: source, error: error);
  }

  void _flashDone() {
    _doneTimer?.cancel();
    setState(() => _showDone = true);
    _doneTimer = Timer(const Duration(milliseconds: 1450), () {
      if (mounted) setState(() => _showDone = false);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
    final recent = app.history.take(4).toList();

    return CliporaPage(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(child: _StudioBackground()),
          Positioned.fill(
            child: ListView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 118),
              children: [
                _StudioHeader(hasBackend: hasBackend),
                const SizedBox(height: 18),
                _StageRail(stage: _stage, hasPlan: _plan.isNotEmpty),
                const SizedBox(height: 16),
                _InputPanel(
                  controller: controller,
                  urlCount: urls.length,
                  matches: matches,
                  hasBackend: hasBackend,
                  busy: app.busy,
                  clipboardUrl: clipboardUrl,
                  onChanged: _onInputChanged,
                  onPaste: _readClipboard,
                  onClear: () {
                    setState(() {
                      controller.clear();
                      _plan = const [];
                      _selected.clear();
                      _error = null;
                      _stage = _StudioStage.paste;
                    });
                  },
                  onAnalyze: _analyze,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ProblemPanel(message: _error!),
                ],
                if (app.status != null) ...[
                  const SizedBox(height: 12),
                  _LivePanel(status: app.status!, busy: app.busy, hasErrors: app.lastRunHadErrors),
                ],
                const SizedBox(height: 16),
                _ArchitecturePanel(hasBackend: hasBackend),
                if (_plan.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PickerPanel(
                    posts: _plan,
                    selected: _selected,
                    selectedCount: _selectedCount,
                    totalCount: _mediaCount,
                    busy: app.busy,
                    onToggle: (key, selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(key);
                        } else {
                          _selected.remove(key);
                        }
                      });
                    },
                    onSelectAll: () {
                      setState(() {
                        _selected.clear();
                        for (var p = 0; p < _plan.length; p++) {
                          for (var m = 0; m < _plan[p].media.length; m++) {
                            _selected.add(_key(p, m));
                          }
                        }
                      });
                    },
                    onClearSelection: () => setState(_selected.clear),
                    onSave: _saveSelected,
                    keyFor: _key,
                  ),
                ],
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _RecentPanel(recent: recent),
                ],
                const SizedBox(height: 20),
                const _CommercialBoundaryPanel(),
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
          if (_showDone) const Positioned.fill(child: IgnorePointer(child: _DoneOverlay())),
        ],
      ),
    );
  }
}

class _StudioHeader extends StatelessWidget {
  const _StudioHeader({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ThreadVaultMark(size: 42, showGlow: false),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Clipora Studio', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
            SizedBox(height: 3),
            Text('Analyze. Pick. Save.', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
        _ModeBadge(hasBackend: hasBackend),
      ],
    );
  }
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.stage, required this.hasPlan});
  final _StudioStage stage;
  final bool hasPlan;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        _StageDot(label: 'Paste', active: stage == _StudioStage.paste || stage == _StudioStage.analyze || hasPlan, done: stage != _StudioStage.paste),
        const _StageLine(),
        _StageDot(label: 'Analyze', active: stage == _StudioStage.analyze || hasPlan, done: hasPlan),
        const _StageLine(),
        _StageDot(label: 'Pick', active: stage == _StudioStage.pick || stage == _StudioStage.save, done: stage == _StudioStage.save),
        const _StageLine(),
        _StageDot(label: 'Save', active: stage == _StudioStage.save, done: false),
      ]),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.controller,
    required this.urlCount,
    required this.matches,
    required this.hasBackend,
    required this.busy,
    required this.clipboardUrl,
    required this.onChanged,
    required this.onPaste,
    required this.onClear,
    required this.onAnalyze,
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
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Drop a link. Clipora builds a save plan first.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.55, height: 1.1)),
              const SizedBox(height: 8),
              Text(
                hasBackend
                    ? 'Resolver Boost follows the yt-dlp style route first. Field capture remains the fallback.'
                    : 'Field Mode runs on this phone. Add a hosted resolver later for the hardest services.',
                style: const TextStyle(color: Colors.white60, height: 1.35, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          _MetricTile(value: urlCount == 0 ? '0' : '$urlCount', label: 'links'),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.newline,
          style: const TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Paste links here — TikTok, Instagram, X, Pinterest, Facebook, Snapchat, YouTube, or Threads…',
            prefixIcon: const Icon(Icons.travel_explore_rounded),
            suffixIcon: controller.text.trim().isEmpty
                ? IconButton(tooltip: 'Paste', onPressed: onPaste, icon: const Icon(Icons.content_paste_go_rounded))
                : IconButton(tooltip: 'Clear', onPressed: onClear, icon: const Icon(Icons.close_rounded)),
          ),
        ),
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: matches.map((match) => _PlatformBadge(match: match, hasBackend: hasBackend)).toList(growable: false),
          ),
        ],
        const SizedBox(height: 16),
        _PrimaryAction(
          icon: Icons.manage_search_rounded,
          label: busy ? 'Working…' : (urlCount > 1 ? 'Analyze $urlCount links' : 'Analyze link'),
          onPressed: busy ? null : onAnalyze,
        ),
        if (clipboardUrl != null && !controller.text.contains(clipboardUrl!)) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: onPaste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Use copied link')),
          ),
        ],
      ]),
    );
  }
}

class _ArchitecturePanel extends StatelessWidget {
  const _ArchitecturePanel({required this.hasBackend});
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_tree_rounded, color: Color(0xFF7DD3FC)),
          const SizedBox(width: 10),
          const Expanded(child: Text('2.0 engine route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          _SoftTag(text: hasBackend ? 'Resolver Boost' : 'Field Mode'),
        ]),
        const SizedBox(height: 14),
        _RouteRow(index: '01', title: 'Analyze', body: 'Build a media plan before touching storage.'),
        _RouteRow(index: '02', title: 'Pick', body: 'Show every detected clip/photo so multi-video and carousel posts are visible.'),
        _RouteRow(index: '03', title: 'Save', body: 'Selected items are byte-checked, downloaded, published, and named cleanly.'),
      ]),
    );
  }
}

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.posts,
    required this.selected,
    required this.selectedCount,
    required this.totalCount,
    required this.busy,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onSave,
    required this.keyFor,
  });

  final List<ResolvedPost> posts;
  final Set<String> selected;
  final int selectedCount;
  final int totalCount;
  final bool busy;
  final void Function(String key, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onSave;
  final String Function(int postIndex, int mediaIndex) keyFor;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.dashboard_customize_rounded, color: Color(0xFFA78BFA)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Media picker • $selectedCount/$totalCount selected',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: onSelectAll, child: const Text('Select all')),
          TextButton(onPressed: onClearSelection, child: const Text('Clear')),
        ]),
        const SizedBox(height: 6),
        for (var p = 0; p < posts.length; p++) ...[
          _PostPickerGroup(
            post: posts[p],
            postIndex: p,
            selected: selected,
            onToggle: onToggle,
            keyFor: keyFor,
          ),
          if (p != posts.length - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 16),
        _PrimaryAction(
          icon: Icons.file_download_done_rounded,
          label: busy ? 'Saving…' : 'Save selected $selectedCount item${selectedCount == 1 ? '' : 's'}',
          onPressed: busy || selectedCount == 0 ? null : onSave,
        ),
      ]),
    );
  }
}

class _PostPickerGroup extends StatelessWidget {
  const _PostPickerGroup({required this.post, required this.postIndex, required this.selected, required this.onToggle, required this.keyFor});
  final ResolvedPost post;
  final int postIndex;
  final Set<String> selected;
  final void Function(String key, bool selected) onToggle;
  final String Function(int postIndex, int mediaIndex) keyFor;

  @override
  Widget build(BuildContext context) {
    final platform = UniversalPlatformDetector.detect(post.sourceUrl);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Icon(platform.icon, color: platform.accent, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(platform.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('${post.author} • ${post.media.length} item${post.media.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
            _SoftTag(text: post.media.length > 1 ? 'carousel' : 'single'),
          ]),
        ),
        for (var m = 0; m < post.media.length; m++)
          _MediaChoice(
            item: post.media[m],
            index: m,
            selected: selected.contains(keyFor(postIndex, m)),
            onChanged: (value) => onToggle(keyFor(postIndex, m), value ?? false),
          ),
      ]),
    );
  }
}

class _MediaChoice extends StatelessWidget {
  const _MediaChoice({required this.item, required this.index, required this.selected, required this.onChanged});
  final ResolvedMedia item;
  final int index;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isVideo = item.kind == MediaKind.video;
    final label = isVideo ? 'Video clip' : 'Photo slide';
    final detail = [
      if (item.width != null && item.height != null) '${item.width}×${item.height}',
      item.mimeType ?? (isVideo ? 'video/mp4' : 'image'),
    ].join(' • ');
    return CheckboxListTile(
      value: selected,
      onChanged: onChanged,
      dense: true,
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: const Color(0xFF00F2EA),
      secondary: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: isVideo ? const [Color(0xFF0EA5E9), Color(0xFF7C3AED)] : const [Color(0xFF10B981), Color(0xFF0F766E)]),
        ),
        child: Icon(isVideo ? Icons.play_arrow_rounded : Icons.image_rounded, color: Colors.white),
      ),
      title: Text('$label ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({required this.status, required this.busy, required this.hasErrors});
  final String status;
  final bool busy;
  final bool hasErrors;

  @override
  Widget build(BuildContext context) {
    final color = hasErrors ? const Color(0xFFFCA5A5) : const Color(0xFF67E8F9);
    return _GlassPanel(
      padding: const EdgeInsets.all(14),
      borderColor: color.withOpacity(.24),
      child: Row(children: [
        Icon(busy ? Icons.sync_rounded : hasErrors ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(status, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, height: 1.35))),
      ]),
    );
  }
}

class _ProblemPanel extends StatelessWidget {
  const _ProblemPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFFFCA5A5).withOpacity(.28),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.report_problem_outlined, color: Color(0xFFFCA5A5)),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFFFE4E6), height: 1.35, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.recent});
  final List<DownloadRecord> recent;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Latest saves', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 10),
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: recent.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = recent[index];
            final ok = item.status == DownloadStatus.completed;
            return Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.055), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withOpacity(.08))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(item.kind == MediaKind.video ? Icons.movie_creation_outlined : Icons.image_outlined, color: ok ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                const Spacer(),
                Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(ok ? 'Saved' : 'Failed', style: TextStyle(fontSize: 12, color: ok ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _CommercialBoundaryPanel extends StatelessWidget {
  const _CommercialBoundaryPanel();

  @override
  Widget build(BuildContext context) {
    return const _GlassPanel(
      child: Text(
        '2.0 boundary: no watermark-removal, no password collection, no private-access bypass. Threads remains on Clipora’s existing local Smart Capture path.',
        style: TextStyle(color: Colors.white60, height: 1.38, fontSize: 12.8, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (hasBackend ? const Color(0xFF7C3AED) : const Color(0xFF0EA5E9)).withOpacity(.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(hasBackend ? Icons.cloud_done_rounded : Icons.phone_android_rounded, size: 15, color: const Color(0xFFDBEAFE)),
        const SizedBox(width: 6),
        Text(hasBackend ? 'Boost' : 'Field', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ]),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.match, required this.hasBackend});
  final PlatformMatch match;
  final bool hasBackend;

  @override
  Widget build(BuildContext context) {
    final route = match.isThreads
        ? 'threads'
        : hasBackend
            ? 'resolver'
            : 'field';
    return CliporaPill(icon: match.icon, label: match.label, value: route, color: match.accent);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x3322D3EE), Color(0x227C3AED)]),
        border: Border.all(color: Colors.white.withOpacity(.12)),
      ),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFFFFFF),
          disabledBackgroundColor: Colors.white.withOpacity(.16),
          foregroundColor: const Color(0xFF05070D),
          disabledForegroundColor: Colors.white38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding = const EdgeInsets.all(16), this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor ?? Colors.white.withOpacity(.09)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.28), blurRadius: 28, offset: const Offset(0, 18))],
      ),
      child: child,
    );
  }
}

class _SoftTag extends StatelessWidget {
  const _SoftTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.08))),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.white70)),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.index, required this.title, required this.body});
  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(index, style: const TextStyle(color: Color(0xFF67E8F9), fontWeight: FontWeight.w900, fontSize: 12)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(body, style: const TextStyle(color: Colors.white54, height: 1.33, fontSize: 12.5)),
        ])),
      ]),
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.label, required this.active, required this.done});
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? const Color(0xFF86EFAC) : active ? const Color(0xFF67E8F9) : Colors.white24;
    return Expanded(
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 14 : 10,
          height: active ? 14 : 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: active ? [BoxShadow(color: color.withOpacity(.35), blurRadius: 14)] : null),
          child: done ? const Icon(Icons.check_rounded, size: 10, color: Color(0xFF06111C)) : null,
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: active ? Colors.white : Colors.white38)),
      ]),
    );
  }
}

class _StageLine extends StatelessWidget {
  const _StageLine();

  @override
  Widget build(BuildContext context) {
    return Container(width: 18, height: 1, margin: const EdgeInsets.only(bottom: 20), color: Colors.white12);
  }
}

class _StudioBackground extends StatelessWidget {
  const _StudioBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF05070D),
        gradient: RadialGradient(
          center: const Alignment(.8, -1.05),
          radius: 1.25,
          colors: [const Color(0xFF1D4ED8).withOpacity(.20), const Color(0xFF05070D)],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [const Color(0xFF00F2EA).withOpacity(.13), Colors.transparent]),
          ),
        ),
      ),
    );
  }
}

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .82, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, value, child) => Transform.scale(scale: value, child: child),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: const Color(0xFF06111C).withOpacity(.94), borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFF86EFAC).withOpacity(.45))),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF86EFAC), size: 58),
            SizedBox(height: 10),
            Text('Saved', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
          ]),
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
