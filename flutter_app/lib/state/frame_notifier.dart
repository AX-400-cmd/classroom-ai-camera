/// 高频帧的可监听容器。
library;

import 'package:flutter/foundation.dart';

import 'package:classroom_camera_app/models/frame_snapshot.dart';

/// 帧以约 4fps 的频率刷新，若走 ChangeNotifier + notifyListeners 会把整棵
/// Widget 树重建掉。这里只让「预览」这一个 ValueListenableBuilder 订阅。
class FrameNotifier extends ValueNotifier<FrameSnapshot?> {
  FrameNotifier() : super(null);

  int _seq = 0;

  /// 单调递增的帧序号，每次成功取帧 +1。
  int get seq => _seq;

  DateTime? _lastFrameAt;

  /// 最近一帧的到达时间，用于估算实际帧率与判断画面是否卡死。
  DateTime? get lastFrameAt => _lastFrameAt;

  void publish(FrameSnapshot snapshot) {
    _seq++;
    _lastFrameAt = DateTime.now();
    value = snapshot;
  }

  void clear() {
    value = null;
  }
}
