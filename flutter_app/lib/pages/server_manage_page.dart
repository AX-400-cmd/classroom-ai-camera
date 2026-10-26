/// 服务器地址管理 + 连接设置。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/server_profile.dart';
import 'package:classroom_camera_app/state/alert_controller.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/widgets/token_dialog.dart';

class ServerManagePage extends StatelessWidget {
  const ServerManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final CameraController controller = context.watch<CameraController>();
    final AlertController alerts = context.watch<AlertController>();

    return Scaffold(
      appBar: AppBar(title: const Text('服务器地址')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _AddSection(controller: controller),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              '已保存的地址（${controller.servers.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (controller.servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('还没有保存任何地址'),
            ),
          for (final ServerProfile p in controller.servers)
            _ServerTile(profile: p, controller: controller),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('连接设置',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          SwitchListTile(
            title: const Text('启动时自动连接上次地址'),
            value: controller.autoConnect,
            onChanged: controller.setAutoConnect,
          ),
          SwitchListTile(
            title: const Text('断线后自动重连'),
            subtitle: const Text('按 1/2/4/8 秒退避重试，最多 8 次'),
            value: controller.autoReconnect,
            onChanged: controller.setAutoReconnect,
          ),
          SwitchListTile(
            title: const Text('在 APP 端绘制目标框'),
            subtitle: const Text('关闭后画面上不显示跟踪框'),
            value: controller.drawOverlay,
            onChanged: controller.setDrawOverlay,
          ),
          SwitchListTile(
            title: const Text('使用无叠加原始画面'),
            subtitle: const Text('关闭则用服务端叠加好目标框的画面'),
            value: controller.rawFrame,
            onChanged: controller.setRawFrame,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('告警设置',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          if (!alerts.notifyReady)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('提示：系统通知不可用（未授权或 Web 端），告警仍会记入列表。'),
            ),
          SwitchListTile(
            title: const Text('启用系统通知'),
            subtitle: const Text('关闭后只保留 APP 内横幅与历史列表'),
            value: alerts.notifyEnabled,
            onChanged: alerts.setNotifyEnabled,
          ),
          if (alerts.needNotifyPermission)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.notifications_off_outlined,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('通知权限未授予')),
                  TextButton(
                    onPressed: alerts.requestNotifyPermission,
                    child: const Text('申请权限'),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            title: const Text('声音与震动'),
            value: alerts.soundVibration,
            onChanged: alerts.setSoundVibration,
          ),
          SwitchListTile(
            title: const Text('免打扰'),
            subtitle: const Text('只记录不弹通知'),
            value: alerts.dnd,
            onChanged: alerts.setDnd,
          ),
        ],
      ),
    );
  }
}

class _AddSection extends StatefulWidget {
  const _AddSection({required this.controller});

  final CameraController controller;

  @override
  State<_AddSection> createState() => _AddSectionState();
}

class _AddSectionState extends State<_AddSection> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String? normalized = normalizeBaseUrl(_url.text);
    if (normalized == null) {
      setState(() => _error = '地址格式不正确，示例：192.168.3.3:8765');
      return;
    }
    setState(() => _error = null);
    try {
      await widget.controller.addServer(
        normalized,
        token: _token.text.trim(),
      );
      if (_name.text.trim().isNotEmpty) {
        await widget.controller.renameServer(normalized, _name.text.trim());
      }
      _url.clear();
      _name.clear();
      _token.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _url,
            decoration: InputDecoration(
              isDense: true,
              labelText: '新增地址',
              hintText: '192.168.3.3:8765',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '备注（可选）',
              hintText: '例如：三楼教室讲台',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '访问令牌（可选）',
              hintText: '后端开启鉴权后才需要填写',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('保存地址'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.profile, required this.controller});

  final ServerProfile profile;
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = controller.baseUrl == profile.baseUrl;

    return ListTile(
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_off,
        color: active ? theme.colorScheme.primary : theme.hintColor,
      ),
      title: Text(profile.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            profile.name.isEmpty
                ? (profile.lastUsed == null
                    ? '未使用过'
                    : '上次使用 ${formatServerTime(profile.lastUsed!.toIso8601String())}')
                : profile.baseUrl,
            overflow: TextOverflow.ellipsis,
          ),
          if (profile.hasToken)
            Text(
              '已设访问令牌',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: profile.hasToken ? '修改访问令牌' : '设置访问令牌',
            icon: Icon(
              profile.hasToken ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 20,
            ),
            onPressed: () async {
              final String? value = await showTokenDialog(
                context,
                initial: profile.token,
                title: profile.displayName,
              );
              if (value == null || !context.mounted) return;
              await controller.setServerToken(profile.baseUrl, value.trim());
            },
          ),
          IconButton(
            tooltip: '重命名',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _rename(context),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => controller.removeServer(profile.id),
          ),
        ],
      ),
      onTap: () {
        controller.connect(profile.baseUrl);
        Navigator.of(context).maybePop();
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final TextEditingController text =
        TextEditingController(text: profile.name);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('备注'),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：三楼教室讲台'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await controller.renameServer(profile.id, result);
  }
}
