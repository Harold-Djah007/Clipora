import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_state.dart';
import '../../models/media_models.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/threadvault_mark.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final completed = state.history.where((e) => e.status == DownloadStatus.completed).length;
    final videos = state.history.where((e) => e.kind == MediaKind.video && e.status == DownloadStatus.completed).length;
    final failed = state.history.where((e) => e.status == DownloadStatus.failed).length;

    return CliporaPage(
      child: Column(children: [
        CliporaSectionTitle(
          title: 'Library',
          subtitle: 'Everything Clipora saved for you',
          trailing: state.history.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear history',
                  onPressed: () => _confirmClear(context, state),
                  icon: const Icon(Icons.delete_sweep_rounded),
                )
              : null,
        ),
        const SizedBox(height: 18),
        CliporaHeroCard(
          child: Row(children: [
            const ThreadVaultMark(size: 66),
            const SizedBox(width: 15),
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                CliporaPill(icon: Icons.download_done_rounded, label: 'Saved', value: '$completed'),
                CliporaPill(icon: Icons.movie_rounded, label: 'Videos', value: '$videos', color: const Color(0xFF34D399)),
                CliporaPill(icon: Icons.warning_amber_rounded, label: 'Failed', value: '$failed', color: const Color(0xFFF87171)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: state.history.isEmpty
              ? Center(
                  child: PremiumCard(
                    glow: true,
                    child: Column(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.grid_view_rounded, size: 44, color: Color(0xFF67E8F9)),
                      SizedBox(height: 12),
                      Text('Your Clipora library is empty', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                      SizedBox(height: 6),
                      Text('Saved videos, photos, carousels and failed jobs will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: state.history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _HistoryTile(item: state.history[index]),
                ),
        ),
      ]),
    );
  }

  void _confirmClear(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear library history?'),
        content: const Text('This clears only the Clipora history list. It does not delete media files already saved on the device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) state.clearHistory();
  }
}

class _HistoryTile extends StatelessWidget {
  final DownloadRecord item;
  const _HistoryTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final isVideo = item.kind == MediaKind.video;
    final isDone = item.status == DownloadStatus.completed;
    return PremiumCard(
      padding: const EdgeInsets.all(13),
      child: Row(children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isVideo
                  ? const [Color(0xFF2563EB), Color(0xFF7C3AED)]
                  : const [Color(0xFF0891B2), Color(0xFF2563EB)],
            ),
          ),
          child: Icon(isVideo ? Icons.play_arrow_rounded : Icons.image_rounded, size: 34, color: Colors.white),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: isDone ? const Color(0xFF22C55E).withOpacity(.13) : const Color(0xFFEF4444).withOpacity(.13),
                ),
                child: Text(isDone ? 'Saved' : 'Failed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDone ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5))),
              ),
            ]),
            const SizedBox(height: 5),
            Text('@${item.author} • ${DateFormat.MMMd().add_jm().format(item.createdAt)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (item.status == DownloadStatus.failed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.error ?? 'Download failed', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12)),
              ),
          ]),
        ),
        const SizedBox(width: 6),
        IconButton(
          onPressed: isDone && File(item.path).existsSync()
              ? () => Share.shareXFiles([XFile(item.path)], text: item.caption)
              : null,
          icon: const Icon(Icons.ios_share_rounded),
        ),
      ]),
    );
  }
}
