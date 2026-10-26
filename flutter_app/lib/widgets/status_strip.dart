/// 手机端窄屏用的紧凑状态条：一行胶囊 + 「详情」按钮。
///
/// 竖屏手机上完整状态面板有 8~10 行，会把预览区挤没，所以这里只留胶囊行，
/// 完整信息放进底部弹层。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/widgets/status_panel.dart';

class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.controller, this.onDetails});

  final CameraController controller;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CameraStatus? s = controller.status;

    final List<Widget> chips = <Widget>[];
    if (s != null) {
      chips.add(StatusChip(
        icon: Icons.person_search,
        label: s.targetStatus,
        color: s.targetStatusCode == TargetStatus.tracking
            ? Colors.green
            : (s.targetStatusCode == TargetStatus.lost
                ? Colors.orange
                : theme.hintColor),
      ));
      chips.add(StatusChip(
        icon: s.recording
            ? Icons.fiber_manual_record
            : Icons.videocam_outlined,
        label: s.recording ? '录制中' : '未在录制',
        color: s.recording ? Colors.red : theme.hintColor,
      ));
      if (s.ptzHasError) {
        chips.add(StatusChip(
          icon: Icons.warning_amber_outlined,
          label: '云台异常',
          color: Colors.orange,
        ));
      }
    } else if (controller.isConnected) {
      chips.add(StatusChip(
        icon: Icons.hourglass_empty,
        label: '获取状态中…',
        color: theme.hintColor,
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 40,
        child: Row(
          children: <Widget>[
            Expanded(
              child: chips.isEmpty
                  ? Text(
                      controller.isConnected ? '暂无状态' : '未连接',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    )
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      children: <Widget>[
                        for (int i = 0; i < chips.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: 8),
                          chips[i],
                        ],
                      ],
                    ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onDetails,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('详情'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出完整状态面板。
Future<void> showStatusSheet(BuildContext context, CameraController controller) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: StatusPanel(controller: controller),
        ),
      );
    },
  );
}
