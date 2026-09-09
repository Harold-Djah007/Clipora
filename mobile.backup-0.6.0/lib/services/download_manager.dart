import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_models.dart';
import 'history_store.dart';
import 'settings_store.dart';

class DownloadManager {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 3),
    followRedirects: true,
    headers: {'User-Agent': 'Mozilla/5.0 ThreadVault/0.6'},
  ));
  final HistoryStore historyStore;

  DownloadManager(this.historyStore);

  Future<List<DownloadRecord>> downloadPost(
    ResolvedPost post,
    AppSettings settings, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/ThreadVault');
    await folder.create(recursive: true);
    final records = await historyStore.load();
    final created = <DownloadRecord>[];

    for (var i = 0; i < post.media.length; i++) {
      final item = post.media[i];
      final ext = item.kind == MediaKind.video ? 'mp4' : 'jpg';
      final base = _filename(settings.filenameTemplate, post, i + 1);
      final path = '${folder.path}/$base.$ext';
      final id = sha1.convert('$path|${DateTime.now().microsecondsSinceEpoch}'.codeUnits).toString();
      var record = DownloadRecord(
        id: id,
        postUrl: post.sourceUrl,
        author: post.author,
        postId: post.postId,
        filename: '$base.$ext',
        path: path,
        kind: item.kind,
        caption: settings.includeCaption ? post.caption : null,
        createdAt: DateTime.now(),
        status: DownloadStatus.downloading,
      );
      try {
        await _dio.download(item.url, path);
        if (settings.includeCaption && post.caption?.trim().isNotEmpty == true) {
          await File('${folder.path}/$base.txt').writeAsString(post.caption!.trim());
        }
        record = record.copyWith(status: DownloadStatus.completed);
      } catch (e) {
        record = record.copyWith(status: DownloadStatus.failed, error: e.toString());
      }
      created.add(record);
      records.insert(0, record);
      await historyStore.save(records);
      onProgress?.call(i + 1, post.media.length);
    }
    return created;
  }

  String _filename(String template, ResolvedPost post, int index) {
    var value = template
        .replaceAll('{author}', post.author)
        .replaceAll('{postId}', post.postId)
        .replaceAll('{index}', index.toString().padLeft(2, '0'));
    value = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return value.isEmpty ? '${post.author}_${post.postId}_$index' : value;
  }
}
