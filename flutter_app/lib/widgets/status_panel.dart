/// 状态面板：跟踪 / 云台 / 录制 / 编码器等信息。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CameraStatus? s = controller.status;

    if (s == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          controller.isConnected ? '正在获取状态…' : '未连接，暂无状态信息',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    }

    final Color trackColor = s.targetStatusCode == TargetStatus.tracking
        ? Colors.green
        : (s.targetStatusCode == TargetStatus.lost ? Colors.orange : theme.hintColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              StatusChip(
                icon: Icons.person_search,
                label: s.targetStatus,
                color: trackColor,
              ),
              StatusChip(
                icon: s.recording ? Icons.fiber_manual_record : Icons.videocam_outlined,
                label: s.recording ? '录制中' : '未在录制',
                color: s.recording ? Colors.red : theme.hintColor,
              ),
              StatusChip(
                icon: Icons.control_camera_outlined,
                label: s.ptzStatus,
                color: s.ptzHasError ? Colors.orange : theme.hintColor,
              ),
              // 行为检测：未开启时不显示，避免混淆
              if (s.behaviorEnabled) ...<Widget>[
                StatusChip(
                  icon: Icons.visibility_outlined,
                  label: s.behaviorHasError
                      ? '检测异常'
                      : (s.behaviorRunning
                          ? '检测中 ${s.behaviorPersons} 人'
                          : '检测启动中…'),
                  color: s.behaviorHasError
                      ? Colors.orange
                      : (s.behaviorRunning ? Colors.teal : theme.hintColor),
                ),
                if (s.behaviorAttention > 0)
                  StatusChip(
                    icon: Icons.remove_red_eye_outlined,
                    label: '注意力不集中 ${s.behaviorAttention}',
                    color: Colors.orange,
                  ),
              ],
            ],
          ),
          if (s.behaviorError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '检测异常：${s.behaviorError}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          _InfoRow(
            label: '画面分辨率',
            value: s.hasFrameSize ? '${s.frameWidth} × ${s.frameHeight}' : '未知',
          ),
          _InfoRow(
            label: '录制编码',
            value: s.recordCodec.isEmpty ? '未知' : s.recordCodec,
            hint: s.recordCodec.toLowerCase() == 'mp4v' ? '浏览器可能无法播放' : null,
            warn: s.recordCodec.toLowerCase() == 'mp4v',
          ),
          if (s.recording && s.recordingName.isNotEmpty)
            _InfoRow(label: '当前文件', value: s.recordingName),
          if (s.outputDir.isNotEmpty)
            _InfoRow(label: '输出目录', value: s.outputDir),
          if (s.serverTime.isNotEmpty)
            _InfoRow(label: '服务器时间', value: formatServerTime(s.serverTime)),
          if (s.recordingPath.isNotEmpty)
            _InfoRow(label: '录制路径', value: s.recordingPath),
        ],
      ),
    );
  }
}

/// 状态胶囊：跟踪 / 录制 / 云台。手机端紧凑状态条也复用它。
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.hint,
    this.warn = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: warn ? Colors.orange.shade800 : null,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.orange.shade800),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
