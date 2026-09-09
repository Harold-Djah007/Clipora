import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_state.dart';
import '../../models/media_models.dart';
import '../../widgets/premium_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 8),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text('Downloads saved on this device', style: TextStyle(color: Colors.white60)),
            ])),
            if (state.history.isNotEmpty)
              IconButton(
                tooltip: 'Clear history',
                onPressed: () => _confirmClear(context, state),
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
          ]),
        ),
        Expanded(
          child: state.history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: PremiumCard(
                      child: Column(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.history_toggle_off_rounded, size: 42),
                        SizedBox(height: 12),
                        Text('Nothing downloaded yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                        SizedBox(height: 6),
                        Text('Completed and failed downloads will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                      ]),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                  itemCount: state.history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = state.history[index];
                    return PremiumCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
                          child: Icon(item.kind == MediaKind.video ? Icons.movie_rounded : Icons.image_rounded),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text('@${item.author} • ${DateFormat.MMMd().add_jm().format(item.createdAt)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            if (item.status == DownloadStatus.failed)
                              Text(item.error ?? 'Download failed', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ]),
                        ),
                        IconButton(
                          onPressed: item.status == DownloadStatus.completed && File(item.path).existsSync()
                              ? () => Share.shareXFiles([XFile(item.path)], text: item.caption)
                              : null,
                          icon: const Icon(Icons.share_rounded),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  void _confirmClear(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This clears the history list. It does not delete media files already saved on the device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) state.clearHistory();
  }
}
