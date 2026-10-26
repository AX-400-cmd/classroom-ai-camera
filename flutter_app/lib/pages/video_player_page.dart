/// 录制视频播放页。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:classroom_camera_app/core/format.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.title,
    required this.url,
    this.poster,
  });

  final String title;
  final String url;

  /// 封面帧地址，加载期间显示在底层。
  final String? poster;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
      await _controller.play();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '视频加载失败：$error';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: '下载',
            icon: const Icon(Icons.download_outlined),
            onPressed: _download,
          ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.error_outline, size: 44, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('改用浏览器打开'),
                    ),
                  ],
                ),
              )
            : _initializing
                ? Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      if (widget.poster != null && widget.poster!.isNotEmpty)
                        Image.network(widget.poster!, fit: BoxFit.contain),
                      const CircularProgressIndicator(),
                    ],
                  )
                : _Stage(controller: _controller),
      ),
    );
  }

  void _download() {
    // 加 disposition=attachment 让后端强制走下载而不是 inline 播放。
    final String url = widget.url.contains('disposition=')
        ? widget.url
        : '${widget.url}&disposition=attachment';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  VideoPlayer(controller),
                  _CenterButton(controller: controller),
                ],
              ),
            ),
          ),
        ),
        _Controls(controller: controller),
      ],
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (BuildContext context, VideoPlayerValue value, Widget? _) {
        if (value.isPlaying) return const SizedBox.shrink();
        return IconButton(
          iconSize: 56,
          color: Colors.white70,
          icon: const Icon(Icons.play_circle_fill),
          onPressed: controller.play,
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (BuildContext context, VideoPlayerValue value, Widget? _) {
        final Duration total = value.duration;
        final Duration pos = value.position;
        final double max = total.inMilliseconds.toDouble();
        final double cur = pos.inMilliseconds.clamp(0, total.inMilliseconds)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: value.isPlaying ? '暂停' : '播放',
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () =>
                    value.isPlaying ? controller.pause() : controller.play(),
              ),
              Text(formatDuration(pos)),
              Expanded(
                child: Slider(
                  value: max <= 0 ? 0 : cur,
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0
                      ? null
                      : (double v) => controller
                          .seekTo(Duration(milliseconds: v.round())),
                ),
              ),
              Text(formatDuration(total)),
              IconButton(
                tooltip: '后退 10 秒',
                icon: const Icon(Icons.replay_10),
                onPressed: () => controller.seekTo(
                  Duration(
                      milliseconds:
                          (pos.inMilliseconds - 10000).clamp(0, 1 << 30)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
