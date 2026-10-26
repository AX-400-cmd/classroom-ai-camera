/// 与帧坐标换算相关的纯几何工具，不依赖任何 Widget，便于单测。
library;

import 'dart:math' as math;
import 'dart:ui';

/// `BoxFit.contain` + `Alignment.center` 下的 letterbox 换算。
///
/// 预览容器尺寸往往和摄像头画面比例不一致（例如 4:3 摄像头放进宽屏容器），
/// 直接用 `点击位置 / 容器宽度` 会把坐标算偏——必须先去掉黑边。
class FrameFit {
  const FrameFit._(
    this.scale,
    this.offsetX,
    this.offsetY,
    this.displayWidth,
    this.displayHeight,
  );

  /// 画面缩放系数。
  final double scale;

  /// 左右黑边宽度（单侧）。
  final double offsetX;

  /// 上下黑边高度（单侧）。
  final double offsetY;

  /// 画面在容器内的实际显示宽度。
  final double displayWidth;

  /// 画面在容器内的实际显示高度。
  final double displayHeight;

  /// 画面是否有效（容器或帧尺寸非法时返回空 fit）。
  bool get isValid => displayWidth > 0 && displayHeight > 0;

  factory FrameFit.contain({required Size container, required Size frame}) {
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        container.width <= 0 ||
        container.height <= 0) {
      return const FrameFit._(1, 0, 0, 0, 0);
    }
    final double scale = math.min(
      container.width / frame.width,
      container.height / frame.height,
    );
    final double dw = frame.width * scale;
    final double dh = frame.height * scale;
    return FrameFit._(
      scale,
      (container.width - dw) / 2,
      (container.height - dh) / 2,
      dw,
      dh,
    );
  }

  /// 把帧像素坐标的目标框 [x, y, w, h] 映射到容器局部坐标。
  Rect mapBox(List<int> box) {
    return Rect.fromLTWH(
      offsetX + box[0] * scale,
      offsetY + box[1] * scale,
      box[2] * scale,
      box[3] * scale,
    );
  }

  /// 把容器局部坐标反算成 0~1 归一化坐标。
  ///
  /// 落在黑边区域时返回 null——调用方应忽略这次点击，而不是把它 clamp 到边缘。
  Offset? toNormalized(Offset point) {
    if (!isValid) return null;
    final double nx = (point.dx - offsetX) / displayWidth;
    final double ny = (point.dy - offsetY) / displayHeight;
    if (nx < 0 || nx > 1 || ny < 0 || ny > 1) return null;
    return Offset(nx, ny);
  }
}
