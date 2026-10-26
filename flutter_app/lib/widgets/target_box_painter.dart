/// 预览画面上的目标框叠加层。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/models/camera_status.dart';

/// 画一个「四角括号」样式的跟踪框，比实心矩形更不遮挡画面。
class TargetBoxPainter extends CustomPainter {
  const TargetBoxPainter({
    required this.rect,
    required this.status,
    this.label,
    this.corner = 16,
  });

  /// 容器局部坐标下的目标框；null 表示当前没有目标。
  final Rect? rect;
  final TargetStatus status;
  final String? label;

  /// 角标长度。
  final double corner;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect? box = rect;
    if (box == null || box.isEmpty) return;

    final Color color = status == TargetStatus.lost
        ? const Color(0xFFFFA726)
        : const Color(0xFF43A047);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // 半透明填充，让框内区域略微提亮，便于确认框住的是谁。
    canvas.drawRect(
      box,
      Paint()..color = color.withValues(alpha: 0.10),
    );

    final double c = corner.clamp(4.0, box.width / 2).toDouble();
    final List<Offset> corners = <Offset>[
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
    ];
    for (final Offset p in corners) {
      final double dx = p.dx == box.left ? c : -c;
      final double dy = p.dy == box.top ? c : -c;
      canvas.drawLine(p, Offset(p.dx + dx, p.dy), stroke);
      canvas.drawLine(p, Offset(p.dx, p.dy + dy), stroke);
    }

    final String? text = label;
    if (text != null && text.isNotEmpty) {
      _drawLabel(canvas, box, text, color);
    }
  }

  void _drawLabel(Canvas canvas, Rect box, String text, Color color) {
    final TextSpan span = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();

    final double left = box.left.clamp(0.0, double.infinity);
    final double top = box.top - tp.height - 6 < 0 ? box.bottom + 6 : box.top - tp.height - 6;
    final Rect bg = Rect.fromLTWH(left, top, tp.width + 12, tp.height + 4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(4)),
      Paint()..color = color,
    );
    tp.paint(canvas, Offset(left + 6, top + 2));
  }

  @override
  bool shouldRepaint(covariant TargetBoxPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.status != status ||
        oldDelegate.label != label;
  }
}
