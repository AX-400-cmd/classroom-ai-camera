/// 行为告警列表页（底部导航第 3 个 tab）。
///
/// 数据来自 [AlertController]，未读数与列表都在这里消费。
library;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/alert_event.dart';
import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/state/alert_controller.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AlertController alerts = context.watch<AlertController>();
    final CameraController camera = context.watch<CameraController>();
    final ThemeData theme = Theme.of(context);

    if (!camera.isConnected) {
      return const _EmptyState(
        icon: Icons.link_off,
        title: '尚未连接服务',
        message: '先在「实时预览」页连上电脑，才能收到行为告警。',
      );
    }

    final List<AlertEvent> items = alerts.visible;
    return Column(
      children: <Widget>[
        _Header(alerts: alerts, count: items.length),
        if (!alerts.notifyEnabled || alerts.dnd)
          _Notice(
            icon: Icons.notifications_off_outlined,
            text: alerts.dnd
                ? '免打扰已开启：告警只进列表，不弹系统通知'
                : '系统通知已关闭：只在 APP 内提示',
          ),
        if (alerts.error != null)
          _Notice(icon: Icons.error_outline, text: alerts.error!, isError: true),
        // 服务端检测状态：让人一眼看出「为什么没触发」
        _BehaviorNotice(status: camera.status),
        // 通知权限没开时，服务端有告警也不会弹系统通知
        _PermissionNotice(alerts: alerts),
        // 诊断行：把插件/权限/最近错误摆出来，排查不用靠猜
        _DiagnosticsLine(alerts: alerts),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(
                  icon: Icons.notifications_none,
                  title: '暂无行为告警',
                  message: camera.status?.behaviorReady == true
                      ? '检测已开启，画面里出现持续玩手机或打瞌睡时会记录在这里。'
                      : '服务端未开启行为检测（启动时未加 --behavior），或模型还在加载。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) =>
                      _AlertTile(event: items[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '提示：APP 需保持在前台才能收到告警。请在系统设置里关闭本应用的电池优化，'
            '并在最近任务中锁定它。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.alerts, required this.count});

  final AlertController alerts;
  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '共 $count 条${alerts.unread > 0 ? ' · 未读 ${alerts.unread}' : ''}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (alerts.unread > 0)
            TextButton(
              onPressed: alerts.markAllRead,
              child: const Text('全部已读'),
            ),
          TextButton.icon(
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('测试'),
            onPressed: () => _sendTest(context),
          ),
          IconButton(
            tooltip: '清空告警',
            icon: const Icon(Icons.delete_outline),
            onPressed: count == 0 ? null : () => _confirmClear(context),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTest(BuildContext context) async {
    try {
      final String message = await alerts.sendTestAlert();
      _toast(context, message);
      await alerts.refresh();
    } catch (error) {
      _toast(context, describeError(error,
          statusCode: error is ApiException ? error.statusCode : null));
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空告警'),
        content: const Text('会同时清除服务端的告警记录，确定继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final String message = await alerts.clear();
      if (context.mounted) _toast(context, message);
    } catch (error) {
      if (context.mounted) {
        _toast(context, describeError(error,
            statusCode: error is ApiException ? error.statusCode : null));
      }
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.event});

  final AlertEvent event;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CameraController camera = context.read<CameraController>();
    final String thumb = camera.api.alertSnapshotUrl(event);
    // 合并后统一一种告警，detail 只作为补充说明
    final IconData icon = event.detail == AlertDetail.phone
        ? Icons.smartphone
        : (event.detail == AlertDetail.sleep ? Icons.bedtime : Icons.remove_red_eye_outlined);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.orange.withValues(alpha: 0.15),
        child: Icon(icon, color: Colors.orange),
      ),
      title: Text(event.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 2),
          Text(_time(event.timestamp)),
          if (event.detailLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(event.detailLabel, style: theme.textTheme.bodySmall),
          ],
          if (event.evidence.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(event.evidence, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
      trailing: thumb.isEmpty
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                thumb,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 48),
              ),
            ),
      onTap: () => _showDetail(context),
    );
  }

  void _showDetail(BuildContext context) {
    final CameraController camera = context.read<CameraController>();
    final String url = camera.api.alertSnapshotUrl(event);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(event.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(_time(event.timestamp)),
              if (event.evidence.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(event.evidence),
              ],
              if (url.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
  }
}

/// 诊断行：显示插件/权限/最近错误，并支持复制到剪贴板。
class _DiagnosticsLine extends StatelessWidget {
  const _DiagnosticsLine({required this.alerts});

  final AlertController alerts;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = alerts.notifyEnabled;
    final bool muted = alerts.dnd;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '通知诊断：${alerts.notifyStatusText}'
              ' 开关=${on ? '开' : '关'} 免打扰=${muted ? '开' : '关'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: '${alerts.notifyStatusText} '
                    '开关=${on ? '开' : '关'} 免打扰=${muted ? '开' : '关'}',
              ));
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }
}

/// 通知权限未授予时的提示 + 一键申请。
///
/// Android 13+ 不授权的话 plugin.show() 会静默失败，
/// 表现就是「列表里有告警，但手机一条通知都不弹」。
class _PermissionNotice extends StatefulWidget {
  const _PermissionNotice({required this.alerts});

  final AlertController alerts;

  @override
  State<_PermissionNotice> createState() => _PermissionNoticeState();
}

class _PermissionNoticeState extends State<_PermissionNotice> {
  @override
  void initState() {
    super.initState();
    // 进页面时查一次真实状态：用户可能已经在系统设置里打开了
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.alerts.refreshNotifyStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AlertController alerts = widget.alerts;
    if (!alerts.needNotifyPermission) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.14),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.notifications_off_outlined,
              size: 18, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '通知权限未开启，收不到系统提醒',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => _request(context),
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }

  Future<void> _request(BuildContext context) async {
    final bool ok = await widget.alerts.requestNotifyPermission();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? '通知权限已开启'
            : '仍未授权，请到 系统设置 → 应用 → 智能课堂 → 通知 手动打开'),
      ));
  }
}

/// 服务端行为检测状态。用来回答「为什么没有告警」。
class _BehaviorNotice extends StatelessWidget {
  const _BehaviorNotice({required this.status});

  final CameraStatus? status;

  @override
  Widget build(BuildContext context) {
    final CameraStatus? s = status;
    if (s == null) return const SizedBox.shrink();
    if (!s.behaviorEnabled) {
      return const _Notice(
        icon: Icons.visibility_off_outlined,
        text: '服务端未开启行为检测：启动命令要加 --behavior',
        isWarn: true,
      );
    }
    if (s.behaviorHasError) {
      return _Notice(
        icon: Icons.error_outline,
        text: '检测异常：${s.behaviorError}',
        isError: true,
      );
    }
    if (!s.behaviorRunning) {
      return const _Notice(
        icon: Icons.hourglass_empty,
        text: '模型加载中，请稍候…',
        isWarn: true,
      );
    }
    if (s.behaviorPersons == 0) {
      return const _Notice(
        icon: Icons.person_off_outlined,
        text: '画面里没检测到人：确认摄像头对着学生、光线充足、人别太远',
        isWarn: true,
      );
    }
    return _Notice(
      icon: Icons.visibility_outlined,
      text: '检测中：画面 ${s.behaviorPersons} 人 · 注意力不集中 ${s.behaviorAttention}',
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.isError = false,
    this.isWarn = false,
  });

  final IconData icon;
  final String text;
  final bool isError;
  final bool isWarn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = isError
        ? theme.colorScheme.error
        : (isWarn ? Colors.orange : theme.colorScheme.primary);
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
