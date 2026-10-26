/// `GET /files` 返回的媒体文件条目。
library;

enum MediaKind { video, image }

MediaKind? parseMediaKind(String? value) {
  switch (value) {
    case 'video':
      return MediaKind.video;
    case 'image':
      return MediaKind.image;
    default:
      return null;
  }
}

class MediaFile {
  const MediaFile({
    required this.name,
    required this.kind,
    required this.size,
    required this.mtime,
    required this.modified,
    required this.recording,
    required this.url,
    this.poster,
  });

  final String name;
  final MediaKind kind;
  final int size;
  final int mtime;
  final String modified;

  /// 是否正是当前正在录制的文件（此时禁止删除）。
  final bool recording;

  /// 相对路径，例如 `/files/download?name=xxx.mp4`。
  final String url;

  /// 视频封面帧地址，图片为 null。
  final String? poster;

  bool get isVideo => kind == MediaKind.video;

  factory MediaFile.fromJson(Map<String, dynamic> json) {
    return MediaFile(
      name: (json['name'] ?? '').toString(),
      kind: parseMediaKind(json['kind']?.toString()) ?? MediaKind.image,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtime: (json['mtime'] as num?)?.toInt() ?? 0,
      modified: (json['modified'] ?? '').toString(),
      recording: json['recording'] == true,
      url: (json['url'] ?? '').toString(),
      poster: json['poster']?.toString(),
    );
  }
}
