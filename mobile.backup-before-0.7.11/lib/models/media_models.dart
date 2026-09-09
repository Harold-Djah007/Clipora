import 'dart:convert';

enum MediaKind { video, image }

enum DownloadStatus { queued, downloading, completed, failed }

class ResolvedMedia {
  final MediaKind kind;
  final String url;
  final int? width;
  final int? height;
  final String? mimeType;

  const ResolvedMedia({
    required this.kind,
    required this.url,
    this.width,
    this.height,
    this.mimeType,
  });
}

class ResolvedPost {
  final String sourceUrl;
  final String postId;
  final String author;
  final String? caption;
  final List<ResolvedMedia> media;

  const ResolvedPost({
    required this.sourceUrl,
    required this.postId,
    required this.author,
    required this.caption,
    required this.media,
  });
}

class DownloadRecord {
  final String id;
  final String postUrl;
  final String author;
  final String postId;
  final String filename;
  final String path;
  final MediaKind kind;
  final String? caption;
  final DateTime createdAt;
  final DownloadStatus status;
  final String? error;

  const DownloadRecord({
    required this.id,
    required this.postUrl,
    required this.author,
    required this.postId,
    required this.filename,
    required this.path,
    required this.kind,
    required this.caption,
    required this.createdAt,
    required this.status,
    this.error,
  });

  DownloadRecord copyWith({DownloadStatus? status, String? error, String? path}) =>
      DownloadRecord(
        id: id,
        postUrl: postUrl,
        author: author,
        postId: postId,
        filename: filename,
        path: path ?? this.path,
        kind: kind,
        caption: caption,
        createdAt: createdAt,
        status: status ?? this.status,
        error: error,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'postUrl': postUrl,
        'author': author,
        'postId': postId,
        'filename': filename,
        'path': path,
        'kind': kind.name,
        'caption': caption,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'error': error,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        id: json['id'] as String,
        postUrl: json['postUrl'] as String,
        author: json['author'] as String,
        postId: json['postId'] as String,
        filename: json['filename'] as String,
        path: json['path'] as String,
        kind: MediaKind.values.byName(json['kind'] as String),
        caption: json['caption'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: DownloadStatus.values.byName(json['status'] as String),
        error: json['error'] as String?,
      );

  static String encodeList(List<DownloadRecord> records) =>
      jsonEncode(records.map((e) => e.toJson()).toList());

  static List<DownloadRecord> decodeList(String raw) =>
      (jsonDecode(raw) as List)
          .map((e) => DownloadRecord.fromJson(e as Map<String, dynamic>))
          .toList();
}
