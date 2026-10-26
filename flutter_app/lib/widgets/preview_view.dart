/// 实时预览：画面 + 目标框叠加 + 点击选目标。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/core/geometry.dart';
import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/models/frame_snapshot.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/widgets/target_box_painter.dart';

class PreviewView extends StatelessWidget {
  const PreviewView({
    super.key,
    required this.controller,
    this.onPickTarget,
    this.onMessage,
  });

  final CameraController controller;

  /// 回调参数是归一化坐标（0~1）。落在黑边上的点击不会回调。
  final void Function(double x, double y)? onPickTarget;

  final void Function(String text)? onMessage;

  @override
  Widget build(BuildContext context) {
    final bool draw = controller.drawOverlay;
    final Size fallback = controller.status?.frameSize ?? Size.zero;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size container =
            Size(constraints.maxWidth, constraints.maxHeight);

        return ValueListenableBuilder<FrameSnapshot?>(
          valueListenable: controller.frames,
          builder: (BuildContext context, FrameSnapshot? snap, Widget? _) {
            final Widget layer = _buildFrame(context, snap, container);
            if (snap == null) return layer;

            final Size frame = snap.hasFrameSize
                ? Size(snap.frameWidth.toDouble(), snap.frameHeight.toDouble())
                : fallback;
            if (frame.width <= 0 || frame.height <= 0) return layer;

            final FrameFit fit =
                FrameFit.contain(container: container, frame: frame);
            if (!fit.isValid) return layer;

            final Rect? box = (draw && snap.targetBox != null)
                ? fit.mapBox(snap.targetBox!)
                : null;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) {
                final Offset? normalized = fit.toNormalized(details.localPosition);
                if (normalized == null) {
                  onMessage?.call('点击位置在画面黑边区域，请点在画面内');
                  return;
                }
                onPickTarget?.call(normalized.dx, normalized.dy);
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  layer,
                  if (draw)
                    CustomPaint(
                      painter: TargetBoxPainter(
                        rect: box,
                        status: snap.targetStatus,
                        label: snap.targetStatus == TargetStatus.tracking
                            ? '跟踪中'
                            : (snap.targetStatus == TargetStatus.lost ? '目标丢失' : null),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFrame(
      BuildContext context, FrameSnapshot? snap, Size container) {
    final Uint8List? bytes = snap?.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const _PreviewPlaceholder(
        icon: Icons.videocam_off_outlined,
        text: '等待画面…',
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          const _PreviewPlaceholder(
        icon: Icons.broken_image_outlined,
        text: '画面解码失败',
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 44, color: theme.disabledColor),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: theme.disabledColor)),
        ],
      ),
    );
  }
}
