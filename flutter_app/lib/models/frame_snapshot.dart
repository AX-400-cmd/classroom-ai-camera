/// 一帧预览画面，附带与这一帧同一时刻的目标框。
library;

import 'dart:typed_data';

import 'package:classroom_camera_app/models/camera_status.dart';

/// 元数据来自 `/frame.jpg` 的响应头（X-Frame-Width / X-Frame-Height /
/// X-Target-Box / X-Target-Status），因此框与画面严格同步，没有 /status 轮询的滞后。
class FrameSnapshot {
  const FrameSnapshot({
    required this.bytes,
    required this.frameWidth,
    required this.frameHeight,
    this.targetBox,
    this.targetStatus = TargetStatus.none,
  });

  final Uint8List bytes;
  final int frameWidth;
  final int frameHeight;
  final List<int>? targetBox;
  final TargetStatus targetStatus;

  bool get hasFrameSize => frameWidth > 0 && frameHeight > 0;
}
