/// 单个录制文件卡片：缩略图 / 名称 / 大小 / 时间 / 操作。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/media_file.dart';
import 'package:classroom_camera_app/state/media_controller.dart';

class MediaTile extends StatelessWidget {
  const MediaTile({
    super.key,
    required this.file,
    required this.controller,
    this.selected = false,
    this.selectMode = false,
    this.onTap,
    this.onLongPress,
    this.onPlay,
    this.onDownload,
    this.onDelete,
  });

  final MediaFile file;
  final MediaController controller;
  final bool selected;
  final bool selectMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool locked = controller.isLocked(file);
    final String thumb = file.isVideo
        ? controller.posterUrl(file)
        : controller.playUrl(file);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _thumb(thumb, theme),
                  if (file.isVideo)
                    const Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 38, color: Colors.white70),
                    ),
                  if (locked)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _badge('录制中', Colors.red, theme),
                    )
                  else if (selectMode)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.white70,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatBytes(file.size)} · ${formatServerTime(file.modified)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (file.isVideo)
                        IconButton(
                          tooltip: '播放',
                          iconSize: 20,
                          icon: const Icon(Icons.play_arrow),
                          onPressed: onPlay,
                        ),
                      IconButton(
                        tooltip: '下载',
                        iconSize: 20,
                        icon: const Icon(Icons.download_outlined),
                        onPressed: onDownload,
                      ),
                      IconButton(
                        tooltip: locked ? '录制中，无法删除' : '删除',
                        iconSize: 20,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: locked ? null : onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String url, ThemeData theme) {
    if (url.isEmpty) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: Icon(
          file.isVideo ? Icons.movie_outlined : Icons.image_outlined,
          color: theme.disabledColor,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      // 后端会为同名文件换内容，加个时间戳避免浏览器缓存旧封面。
      headers: const <String, String>{},
      cacheWidth: 480,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, color: theme.disabledColor),
      ),
      loadingBuilder: (BuildContext context, Widget child,
          ImageChunkEvent? progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _badge(String text, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
