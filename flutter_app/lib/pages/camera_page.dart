/// 主页面：连接 + 预览 + 控制。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/connection_phase.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/state/alert_controller.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/widgets/alert_banner.dart';
import 'package:classroom_camera_app/widgets/connection_banner.dart';
import 'package:classroom_camera_app/widgets/preview_view.dart';
import 'package:classroom_camera_app/widgets/server_field.dart';
import 'package:classroom_camera_app/widgets/status_panel.dart';
import 'package:classroom_camera_app/widgets/status_strip.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({
    super.key,
    this.onOpenServers,
    this.onOpenFiles,
    this.onViewAlerts,
  });

  final VoidCallback? onOpenServers;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onViewAlerts;

  @override
  Widget build(BuildContext context) {
    final CameraController controller = context.watch<CameraController>();
    final AlertController alerts = context.watch<AlertController>();

    return Column(
      children: <Widget>[
        ConnectionBanner(controller: controller),
        AlertBanner(controller: alerts, onView: onViewAlerts),
        _ServerSection(controller: controller, onManage: onOpenServers),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool wide = constraints.maxWidth >= 900;
              final Widget preview = _PreviewArea(controller: controller);

              if (!wide) {
                return Column(
                  children: <Widget>[
                    Expanded(child: preview),
                    const Divider(height: 1),
                    StatusStrip(
                      controller: controller,
                      onDetails: () => showStatusSheet(context, controller),
                    ),
                    _ControlBar(controller: controller),
                  ],
                );
              }

              return Row(
                children: <Widget>[
                  Expanded(child: preview),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: SingleChildScrollView(
                            child: StatusPanel(controller: controller),
                          ),
                        ),
                        const Divider(height: 1),
                        _ControlBar(controller: controller),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServerSection extends StatefulWidget {
  const _ServerSection({required this.controller, this.onManage});

  final CameraController controller;
  final VoidCallback? onManage;

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  bool _collapsed = true;

  @override
  void didUpdateWidget(covariant _ServerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool now = widget.controller.isConnected;
    if (now != oldWidget.controller.isConnected) {
      // 连上了自动收起，断线自动展开方便改地址。
      setState(() => _collapsed = now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CameraController controller = widget.controller;
    final ThemeData theme = Theme.of(context);

    // 已连接且未展开 → 收成一行，把竖向空间让给预览。
    final bool slim = _collapsed && controller.isConnected;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: slim
          ? InkWell(
              onTap: () => setState(() => _collapsed = false),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.baseUrl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '展开地址设置',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      onPressed: () => setState(() => _collapsed = false),
                    ),
                  ],
                ),
              ),
            )
          : ServerField(controller: controller, onManage: widget.onManage),
    );
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool connected = controller.isConnected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PreviewView(
                controller: controller,
                onPickTarget: (double x, double y) => _pick(context, x, y),
                onMessage: (String text) => _toast(context, text),
              ),
              if (!connected)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.link_off, size: 40, color: Colors.white70),
                      const SizedBox(height: 8),
                      Text(
                        controller.phase == ConnectionPhase.idle
                            ? '填写上方地址后点击「连接」'
                            : controller.phase.label,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      connected ? '点击画面选择跟踪目标' : '未连接',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, double x, double y) async {
    try {
      final String message = await controller.selectTarget(x, y);
      if (context.mounted) _toast(context, message);
    } catch (error) {
      if (context.mounted) {
        _toast(context, describeError(error,
            statusCode: error is ApiException ? error.statusCode : null));
      }
    }
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final bool connected = controller.isConnected;
    final bool busy = controller.isBusy;
    final bool recording = controller.recording;
    final CameraAction pending = controller.pending;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: <Widget>[
          FilledButton.icon(
            onPressed: (!connected || busy) ? null : () => _run(context, () {
                  return recording
                      ? controller.stopRecording()
                      : controller.startRecording();
                }),
            icon: _pendingIcon(pending == CameraAction.start ||
                    pending == CameraAction.stop,
                recording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(recording ? '停止录制' : '开始录制'),
            style: recording
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error)
                : null,
          ),
          OutlinedButton.icon(
            onPressed: (!connected || busy)
                ? null
                : () => _run(context, controller.takeSnapshot),
            icon: _pendingIcon(pending == CameraAction.snapshot, Icons.photo_camera_outlined),
            label: const Text('截图'),
          ),
          OutlinedButton.icon(
            onPressed: (!connected || busy)
                ? null
                : () => _run(context, controller.clearTarget),
            icon: _pendingIcon(
                pending == CameraAction.clearTarget, Icons.person_off_outlined),
            label: const Text('取消跟踪'),
          ),
        ],
      ),
    );
  }

  Widget _pendingIcon(bool active, IconData icon) {
    if (!active) return Icon(icon, size: 18);
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _run(BuildContext context, Future<String> Function() body) async {
    try {
      final String message = await body();
      if (context.mounted && message.isNotEmpty) _toast(context, message);
    } catch (error) {
      if (context.mounted) {
        _toast(context, describeError(error,
            statusCode: error is ApiException ? error.statusCode : null));
      }
    }
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}
