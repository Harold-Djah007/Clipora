import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_models.dart';
import 'history_store.dart';
import 'platform_services.dart';
import 'settings_store.dart';

class DownloadManager {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 8),
    followRedirects: true,
    maxRedirects: 8,
    validateStatus: (status) => status != null && status >= 200 && status < 400,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 Chrome/152.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
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
    final folder = Directory('${root.path}/Clipora');
    await folder.create(recursive: true);
    final records = await historyStore.load();
    final created = List<DownloadRecord?>.filled(post.media.length, null);
    final total = post.media.length;
    if (total == 0) return const [];

    var next = 0;
    var completed = 0;
    final concurrency = math.min(total, settings.maxConcurrentDownloads.clamp(1, 6).toInt());

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= total) return;
        final record = await _downloadOne(
          post: post,
          item: post.media[i],
          index: i + 1,
          total: total,
          folder: folder,
          settings: settings,
        );
        created[i] = record;
        records.insert(0, record);
        await historyStore.save(records);
        completed += 1;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return created.whereType<DownloadRecord>().toList(growable: false);
  }

  Future<DownloadRecord> _downloadOne({
    required ResolvedPost post,
    required ResolvedMedia item,
    required int index,
    required int total,
    required Directory folder,
    required AppSettings settings,
  }) async {
    final ext = _extension(item);
    final base = _filename(settings.filenameTemplate, post, index);
    final path = await _uniquePath(folder.path, base, ext);
    final fileName = File(path).uri.pathSegments.last;
    final id = sha1.convert('$path|${DateTime.now().microsecondsSinceEpoch}'.codeUnits).toString();
    var record = DownloadRecord(
      id: id,
      postUrl: post.sourceUrl,
      author: post.author,
      postId: post.postId,
      filename: fileName,
      path: path,
      kind: item.kind,
      caption: settings.includeCaption ? post.caption : null,
      createdAt: DateTime.now(),
      status: DownloadStatus.downloading,
    );

    try {
      final uri = Uri.tryParse(item.url);
      debugPrint('[Clipora] download $index/$total ${item.kind.name} host=${uri?.host ?? 'unknown'}');
      if (!_isSafePostMediaUrl(item.url)) {
        throw StateError('Skipped a non-post Threads page asset. No unrelated PNG/audio was saved.');
      }

      final temp = File('$path.part');
      if (await temp.exists()) await temp.delete();
      await _dio.download(
        item.url,
        temp.path,
        options: Options(
          headers: {
            'Accept': item.kind == MediaKind.video ? 'video/mp4,video/*,*/*' : 'image/avif,image/webp,image/apng,image/*,*/*',
            'Referer': post.sourceUrl.startsWith('http') ? post.sourceUrl : 'https://www.threads.com/',
          },
        ),
      );
      if (!await temp.exists() || await temp.length() < 256) {
        throw const FileSystemException('Downloaded file was empty or incomplete.');
      }

      final detected = await _detectMediaKind(temp);
      if (detected == null) {
        throw const FileSystemException('Threads returned an unsupported file instead of post media.');
      }
      if (item.kind == MediaKind.video && detected != _DetectedMediaKind.video) {
        throw const FileSystemException('Expected a Threads video but the server returned an image/audio/static asset.');
      }
      if (item.kind == MediaKind.image && detected != _DetectedMediaKind.image) {
        throw const FileSystemException('Expected a Threads image but the server returned another file type.');
      }

      await temp.rename(path);

      final mime = item.mimeType ?? (item.kind == MediaKind.video ? 'video/mp4' : 'image/jpeg');
      await PlatformServices.publishDownload(
        sourcePath: path,
        fileName: fileName,
        mimeType: mime,
      );

      if (settings.includeCaption && post.caption?.trim().isNotEmpty == true) {
        final captionPath = await _uniquePath(folder.path, base, 'txt');
        final captionName = File(captionPath).uri.pathSegments.last;
        await File(captionPath).writeAsString(post.caption!.trim(), flush: true);
        await PlatformServices.publishDownload(
          sourcePath: captionPath,
          fileName: captionName,
          mimeType: 'text/plain',
        );
      }
      debugPrint('[Clipora] saved ${item.kind.name}: $fileName');
      record = record.copyWith(status: DownloadStatus.completed);
    } catch (e, st) {
      debugPrint('[Clipora] media download failed: $e\n$st');
      try {
        final partial = File('$path.part');
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      record = record.copyWith(status: DownloadStatus.failed, error: _friendlyError(e));
    }
    return record;
  }

  Future<String> _uniquePath(String folder, String base, String ext) async {
    var candidate = '$folder/$base.$ext';
    if (!await File(candidate).exists() && !await File('$candidate.part').exists()) return candidate;
    for (var i = 2; i < 1000; i++) {
      candidate = '$folder/${base}_$i.$ext';
      if (!await File(candidate).exists() && !await File('$candidate.part').exists()) return candidate;
    }
    return '$folder/${base}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  bool _isSafePostMediaUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return false;
    final lower = raw.toLowerCase();
    final host = uri.host.toLowerCase();
    if (host == 'static.cdninstagram.com') return false;
    if (lower.contains('/rsrc.php/') || lower.contains('/static/')) return false;
    if (lower.contains('sprite') || lower.contains('favicon')) return false;
    if (lower.contains('mime_type=audio') || lower.contains('/audio/')) return false;
    final goodHost = host.contains('cdninstagram.com') || host.contains('fbcdn.net');
    if (!goodHost) return false;
    if (lower.contains('.mp4') || lower.contains('mime_type=video')) return true;
    if (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp')) return true;
    return false;
  }

  Future<_DetectedMediaKind?> _detectMediaKind(File file) async {
    final length = await file.length();
    if (length < 12) return null;
    final raf = await file.open();
    try {
      final bytes = await raf.read(math.min(length, 128));
      if (_isMp4(bytes)) return _DetectedMediaKind.video;
      if (_isJpeg(bytes) || _isPng(bytes) || _isWebp(bytes)) return _DetectedMediaKind.image;
      if (_isLikelyAudio(bytes)) return null;
      return null;
    } finally {
      await raf.close();
    }
  }

  bool _isMp4(List<int> b) {
    if (b.length < 12) return false;
    for (var i = 0; i <= b.length - 4 && i < 32; i++) {
      if (b[i] == 0x66 && b[i + 1] == 0x74 && b[i + 2] == 0x79 && b[i + 3] == 0x70) {
        return true;
      }
    }
    return false;
  }

  bool _isJpeg(List<int> b) => b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  bool _isPng(List<int> b) =>
      b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A;

  bool _isWebp(List<int> b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;

  bool _isLikelyAudio(List<int> b) {
    if (b.length < 4) return false;
    final id3 = b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33;
    final ogg = b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53;
    final wav = b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x41 && b[10] == 0x56 && b[11] == 0x45;
    return id3 || ogg || wav;
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
    final text = error.toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('FileSystemException: ', '')
        .replaceFirst('StateError: ', '');
    return text;
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

enum _DetectedMediaKind { video, image }
