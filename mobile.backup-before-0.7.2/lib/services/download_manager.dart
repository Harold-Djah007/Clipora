import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_models.dart';
import 'history_store.dart';
import 'platform_services.dart';
import 'settings_store.dart';

class DownloadManager {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(minutes: 5),
    followRedirects: true,
    maxRedirects: 6,
    validateStatus: (status) => status != null && status >= 200 && status < 400,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 Chrome/124.0 Safari/537.36',
      'Accept': '*/*',
      'Referer': 'https://www.threads.com/',
    },
  ));
  final HistoryStore historyStore;

  DownloadManager(this.historyStore);

  Future<List<DownloadRecord>> downloadPost(
    ResolvedPost post,
    AppSettings settings, {
    void Function(int completed, int total)? onProgress,
  }) async {
    if (settings.wifiOnly && !await PlatformServices.isOnWifi()) {
      throw StateError('Wi-Fi only is enabled. Connect to Wi-Fi or disable it in Settings.');
    }

    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/ThreadVault');
    await folder.create(recursive: true);
    final records = await historyStore.load();
    final created = <DownloadRecord>[];

    for (var i = 0; i < post.media.length; i++) {
      final item = post.media[i];
      final ext = _extension(item);
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
        final temp = File('$path.part');
        if (await temp.exists()) await temp.delete();
        await _dio.download(item.url, temp.path);
        if (!await temp.exists() || await temp.length() < 256) {
          throw const FileSystemException('Downloaded file was empty or incomplete.');
        }
        await temp.rename(path);

        final mime = item.mimeType ?? (item.kind == MediaKind.video ? 'video/mp4' : 'image/jpeg');
        await PlatformServices.publishDownload(
          sourcePath: path,
          fileName: '$base.$ext',
          mimeType: mime,
        );

        if (settings.includeCaption && post.caption?.trim().isNotEmpty == true) {
          final captionPath = '${folder.path}/$base.txt';
          await File(captionPath).writeAsString(post.caption!.trim(), flush: true);
          await PlatformServices.publishDownload(
            sourcePath: captionPath,
            fileName: '$base.txt',
            mimeType: 'text/plain',
          );
        }
        record = record.copyWith(status: DownloadStatus.completed);
      } catch (e) {
        try {
          final partial = File('$path.part');
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
        record = record.copyWith(status: DownloadStatus.failed, error: _friendlyError(e));
      }

      created.add(record);
      records.insert(0, record);
      await historyStore.save(records);
      onProgress?.call(i + 1, post.media.length);
    }
    return created;
  }

  String _extension(ResolvedMedia item) {
    if (item.kind == MediaKind.video) return 'mp4';
    final mime = item.mimeType?.toLowerCase();
    if (mime == 'image/png') return 'png';
    if (mime == 'image/webp') return 'webp';
    return 'jpg';
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code == 403) return 'Threads media link expired or access was denied. Retry the post to refresh the link.';
      if (code == 404) return 'Threads media is no longer available.';
      if (code != null) return 'Download server returned HTTP $code.';
      return 'Network download failed: ${error.message ?? error.type.name}';
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  String _filename(String template, ResolvedPost post, int index) {
    var value = template
        .replaceAll('{author}', post.author)
        .replaceAll('{postId}', post.postId)
        .replaceAll('{index}', index.toString().padLeft(2, '0'));
    value = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (value.length > 120) value = value.substring(0, 120);
    return value.isEmpty ? '${post.author}_${post.postId}_$index' : value;
  }
}
