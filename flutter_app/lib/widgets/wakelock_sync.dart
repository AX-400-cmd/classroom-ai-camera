/// 根据条件保持屏幕常亮。
///
/// 监控类 APP 最烦的就是看着看着屏幕熄了，这里把它做成一个声明式小部件：
/// `enabled` 变化时自动开关，离开页面时恢复。
library;

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class WakelockSync extends StatefulWidget {
  const WakelockSync({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<WakelockSync> createState() => _WakelockSyncState();
}

class _WakelockSyncState extends State<WakelockSync> {
  @override
  void initState() {
    super.initState();
    _apply(widget.enabled);
  }

  @override
  void didUpdateWidget(covariant WakelockSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _apply(widget.enabled);
  }

  void _apply(bool on) {
    // 平台通道失败不该影响 UI，吞掉异常即可。
    try {
      on ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {}
  }

  @override
  void dispose() {
    _apply(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
