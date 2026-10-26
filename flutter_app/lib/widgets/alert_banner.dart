/// APP 内告警横幅：预览页顶部出现，5 秒后自动收起。
///
/// 只在挂载后**新到达**的告警才弹（启动时的历史告警不打扰）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/models/alert_event.dart';
import 'package:classroom_camera_app/state/alert_controller.dart';

class AlertBanner extends StatefulWidget {
  const AlertBanner({super.key, required this.controller, this.onView});

  final AlertController controller;
  final VoidCallback? onView;

  @override
  State<AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<AlertBanner> {
  String _baselineId = '';
  AlertEvent? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 已有历史不应在进页面时弹窗，先记下基线
    _baselineId = widget.controller.latest?.id ?? '';
  }

  @override
  void didUpdateWidget(covariant AlertBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final AlertEvent? latest = widget.controller.latest;
    if (latest == null || latest.id == _baselineId) return;
    _baselineId = latest.id;
    _shown = latest;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _shown = null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AlertEvent? event = _shown;
    final ThemeData theme = Theme.of(context);
    final bool isPhone = event?.detail == AlertDetail.phone;
    final Color color = Colors.orange;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: event == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: color.withValues(alpha: 0.16),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    isPhone ? Icons.smartphone : Icons.bedtime,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          event.title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (event.evidence.isNotEmpty)
                          Text(
                            event.evidence,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onView,
                    child: const Text('查看'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _shown = null),
                  ),
                ],
              ),
            ),
    );
  }
}
