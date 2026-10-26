/// 顶部连接状态条：状态色块 + 可读错误 + 操作按钮。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/models/connection_phase.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ConnectionPhase phase = controller.phase;
    final String? error = controller.errorMessage;

    if (phase == ConnectionPhase.connected && error == null) {
      return const SizedBox.shrink();
    }

    final Color color = phase.color;
    final bool busy = phase.isBusy;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 16,
              height: 16,
              child: busy
                  ? CircularProgressIndicator(strokeWidth: 2, color: color)
                  : Icon(_iconOf(phase), size: 18, color: color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  phase.label + (controller.baseUrl.isEmpty ? '' : '  ${controller.baseUrl}'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: color),
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(error, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    _hintFor(error, controller.baseUrl),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ],
            ),
          ),
          if (phase == ConnectionPhase.failed)
            TextButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          if (busy && controller.autoReconnect)
            TextButton(
              onPressed: controller.disconnect,
              child: const Text('停止'),
            ),
        ],
      ),
    );
  }

  static IconData _iconOf(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return Icons.info_outline;
      case ConnectionPhase.connecting:
      case ConnectionPhase.reconnecting:
        return Icons.sync;
      case ConnectionPhase.connected:
        return Icons.check_circle_outline;
      case ConnectionPhase.failed:
        return Icons.error_outline;
    }
  }

  /// 在错误原因后面补一条「接下来该干什么」，否则用户只知道坏了不知道怎么修。
  static String _hintFor(String error, String baseUrl) {
    if (error.contains('摄像头画面尚未准备好')) {
      return '请确认摄像头没被其它程序占用，然后重启服务';
    }
    if (error.contains('浏览器拒绝') || error.contains('网络错误')) {
      return '在电脑上确认服务已启动；若用局域网 IP，需与电脑处在同一网络';
    }
    if (error.contains('超时') || error.contains('拒绝')) {
      return '检查服务是否运行、IP 与端口是否正确（可在电脑上打开 '
          '${baseUrl.isEmpty ? '服务地址' : baseUrl}/status 验证）';
    }
    return '可点击「重试」重新连接，或在下方修改服务地址';
  }
}
