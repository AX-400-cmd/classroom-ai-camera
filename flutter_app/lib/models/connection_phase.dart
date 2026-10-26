/// 连接状态机。
library;

import 'package:flutter/material.dart';

enum ConnectionPhase {
  /// 未连接，不发起任何请求。
  idle,

  /// 正在探测/连接中。
  connecting,

  /// 已连接，帧与状态轮询运行中。
  connected,

  /// 连接中断，正在按退避策略重试。
  reconnecting,

  /// 连接失败且已停止重试。
  failed,
}

extension ConnectionPhaseX on ConnectionPhase {
  bool get isBusy => this == ConnectionPhase.connecting || this == ConnectionPhase.reconnecting;

  bool get isConnected => this == ConnectionPhase.connected;

  /// 是否应该在后台跑轮询循环。只有已连接才跑——这是"未连接时空刷请求"的修复点。
  bool get shouldPoll => this == ConnectionPhase.connected;

  String get label {
    switch (this) {
      case ConnectionPhase.idle:
        return '未连接';
      case ConnectionPhase.connecting:
        return '正在连接…';
      case ConnectionPhase.connected:
        return '已连接';
      case ConnectionPhase.reconnecting:
        return '连接中断，正在重试';
      case ConnectionPhase.failed:
        return '连接失败';
    }
  }

  Color get color {
    switch (this) {
      case ConnectionPhase.idle:
        return Colors.grey;
      case ConnectionPhase.connecting:
      case ConnectionPhase.reconnecting:
        return Colors.orange;
      case ConnectionPhase.connected:
        return Colors.green;
      case ConnectionPhase.failed:
        return Colors.red;
    }
  }
}
