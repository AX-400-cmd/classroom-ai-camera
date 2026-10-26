/// 录制文件管理页：列表 / 搜索 / 播放 / 下载 / 删除。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/media_file.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/state/media_controller.dart';
import 'package:classroom_camera_app/pages/video_player_page.dart';
import 'package:classroom_camera_app/widgets/media_tile.dart';

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, this.onGoConnect});

  /// 未连接时「去连接」的跳转回调，由外层切换到预览页。
  final VoidCallback? onGoConnect;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool? _wasConnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool connected = context.read<CameraController>().isConnected;
    if (_wasConnected != connected) {
      final bool first = _wasConnected == null;
      _wasConnected = connected;
      // 连接状态变化时（含刚连上、断线重连）重新拉一次列表。
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
      }
    }
  }

  void _reload() {
    if (!mounted) return;
    context.read<MediaController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController camera = context.watch<CameraController>();
    final MediaController media = context.watch<MediaController>();
    final ThemeData theme = Theme.of(context);

    if (!camera.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.folder_off_outlined, size: 46, color: theme.disabledColor),
              const SizedBox(height: 12),
              const Text('需要先连接到服务才能查看录制文件'),
              const SizedBox(height: 12),
              if (widget.onGoConnect == null)
                const SizedBox.shrink()
              else
                FilledButton.icon(
                  onPressed: widget.onGoConnect,
                  icon: const Icon(Icons.link),
                  label: const Text('去连接'),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        _Toolbar(media: media),
        if (media.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: <Widget>[
                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(media.error!, style: theme.textTheme.bodySmall),
                ),
                TextButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          ),
        Expanded(
          child: media.loading && media.files.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _Grid(media: media),
        ),
        if (media.selectMode) _SelectionBar(media: media),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.media});

  final MediaController media;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                hintText: '按文件名搜索',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(),
              ),
              onChanged: media.setKeyword,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => media.refresh(),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'all', child: Text('显示全部')),
              const PopupMenuItem<String>(value: 'video', child: Text('只看视频')),
              const PopupMenuItem<String>(value: 'image', child: Text('只看图片')),
              const PopupMenuItem<String>(value: 'select', child: Text('批量选择')),
            ],
            onSelected: (String value) {
              switch (value) {
                case 'video':
                  media.setKindFilter(MediaKind.video);
                  break;
                case 'image':
                  media.setKindFilter(MediaKind.image);
                  break;
                case 'select':
                  media.enterSelectMode();
                  break;
                default:
                  media.setKindFilter(null);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.media});

  final MediaController media;

  @override
  Widget build(BuildContext context) {
    final List<MediaFile> files = media.files;

    // RefreshIndicator 需要可滚动内容，空态也用 ListView 撑起来才能下拉刷新。
    return RefreshIndicator(
      onRefresh: () => media.refresh(),
      child: files.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                Center(
                  child: Text(
                    media.totalCount == 0 ? '还没有录制文件' : '没有匹配的文件',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int cross = (constraints.maxWidth / 190).floor().clamp(2, 6);
                return GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: files.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _buildTile(context, files[index]),
                );
              },
            ),
    );
  }

  Widget _buildTile(BuildContext context, MediaFile file) {
    final MediaController media = context.read<MediaController>();
    final bool locked = media.isLocked(file);
    return MediaTile(
      file: file,
      controller: media,
      selectMode: media.selectMode,
      selected: media.isSelected(file.name),
      onTap: media.selectMode && !locked
          ? () => media.toggleSelected(file.name)
          : (file.isVideo ? () => _open(context, file) : null),
      onLongPress: locked ? null : () => media.enterSelectMode(file.name),
      onPlay: file.isVideo ? () => _open(context, file) : null,
      onDownload: () => _download(context, file),
      onDelete: locked ? null : () => _confirmDelete(context, file),
    );
  }

  void _open(BuildContext context, MediaFile file) {
    final MediaController media = context.read<MediaController>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => VideoPlayerPage(
          title: file.name,
          url: media.playUrl(file),
          poster: media.posterUrl(file),
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, MediaFile file) async {
    final MediaController media = context.read<MediaController>();
    final Uri uri = Uri.parse(media.downloadUrl(file));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开下载链接')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, MediaFile file) async {
    final MediaController media = context.read<MediaController>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除「${file.name}」？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final String message = await media.delete(file.name);
      if (context.mounted) _toast(context, message);
    } catch (error) {
      if (context.mounted) _toast(context, describeError(error));
    }
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.media});

  final MediaController media;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int n = media.selected.length;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: <Widget>[
            Text('已选 $n 项'),
            const SizedBox(width: 8),
            TextButton(
              onPressed: media.selectAllVisible,
              child: const Text('全选'),
            ),
            const Spacer(),
            TextButton(
              onPressed: media.exitSelectMode,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: n == 0 ? null : () => _runDelete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDelete(BuildContext context) async {
    final MediaController media = context.read<MediaController>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${media.selected.length} 个文件？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final DeleteResult result = await media.deleteSelected();
    if (!context.mounted) return;
    final String text = result.allOk
        ? '已删除 ${result.deleted} 个文件'
        : '删除 ${result.deleted}/${result.total} 个${result.firstError == null ? '' : '，失败原因：${result.firstError}'}';
    _toast(context, text);
    if (result.deleted > 0) media.exitSelectMode();
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}
