/// 服务地址输入 + 历史地址下拉 + 连接按钮。
library;

import 'package:flutter/material.dart';

import 'package:classroom_camera_app/models/connection_phase.dart';
import 'package:classroom_camera_app/models/server_profile.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';
import 'package:classroom_camera_app/widgets/token_dialog.dart';

class ServerField extends StatefulWidget {
  const ServerField({
    super.key,
    required this.controller,
    this.onManage,
  });

  final CameraController controller;
  final VoidCallback? onManage;

  @override
  State<ServerField> createState() => _ServerFieldState();
}

class _ServerFieldState extends State<ServerField> {
  late final TextEditingController _text;
  String? _inlineError;
  /// null = 未改动，连接时沿用档案里保存的令牌；空串 = 明确不用令牌。
  String? _token;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.baseUrl);
  }

  @override
  void didUpdateWidget(covariant ServerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部改了地址（例如从历史里选）而输入框没聚焦时同步过去，避免覆盖用户输入。
    final String current = widget.controller.baseUrl;
    if (current.isNotEmpty &&
        current != _text.text &&
        !FocusScope.of(context).hasFocus) {
      _text.text = current;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 当前生效的令牌：优先用户本次输入，其次该地址档案里保存的。
  String _effectiveToken() {
    if (_token != null) return _token!;
    final String? url = normalizeBaseUrl(_text.text);
    if (url == null) return '';
    for (final ServerProfile p in widget.controller.servers) {
      if (p.baseUrl == url) return p.token;
    }
    return '';
  }

  Future<void> _editToken() async {
    final String? result = await showTokenDialog(
      context,
      initial: _effectiveToken(),
    );
    if (!mounted || result == null) return;
    setState(() => _token = result.trim());
  }

  void _connect() {
    final String input = _text.text;
    if (input.trim().isEmpty) {
      setState(() => _inlineError = '请先填写服务地址');
      return;
    }
    setState(() => _inlineError = null);
    FocusScope.of(context).unfocus();
    widget.controller.connect(input, token: _token);
  }

  @override
  Widget build(BuildContext context) {
    final CameraController controller = widget.controller;
    final bool busy = controller.phase.isBusy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _text,
              decoration: InputDecoration(
                isDense: true,
                labelText: '服务地址',
                hintText: 'http://192.168.3.3:8765',
                errorText: _inlineError,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                suffixIcon: _HistoryButton(
                  controller: controller,
                  onPick: (ServerProfile p) {
                    _text.text = p.baseUrl;
                    // 换地址后改用该地址档案里保存的令牌，而不是上一次手填的
                    _token = null;
                    setState(() => _inlineError = null);
                  },
                ),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
              onChanged: (_) {
                if (_inlineError != null) setState(() => _inlineError = null);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _effectiveToken().isEmpty ? '访问令牌（未设置）' : '访问令牌（已设置）',
            icon: Icon(
              _effectiveToken().isEmpty ? Icons.lock_open_outlined : Icons.lock_outline,
              size: 20,
            ),
            onPressed: _editToken,
          ),
          FilledButton.icon(
            onPressed: busy ? null : _connect,
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(controller.isConnected ? Icons.link : Icons.link_outlined,
                    size: 18),
            label: Text(controller.isConnected ? '重连' : '连接'),
          ),
          if (widget.onManage != null)
            IconButton(
              tooltip: '管理地址',
              icon: const Icon(Icons.settings_outlined),
              onPressed: widget.onManage,
            ),
        ],
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.controller, required this.onPick});

  final CameraController controller;
  final void Function(ServerProfile) onPick;

  @override
  Widget build(BuildContext context) {
    final List<ServerProfile> servers = controller.servers;
    if (servers.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<ServerProfile>(
      tooltip: '历史地址',
      icon: const Icon(Icons.history, size: 20),
      itemBuilder: (BuildContext context) => servers
          .map(
            (ServerProfile p) => PopupMenuItem<ServerProfile>(
              value: p,
              child: SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      p.name.isEmpty ? p.baseUrl : p.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (p.name.isNotEmpty)
                      Text(
                        p.baseUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
      onSelected: onPick,
    );
  }
}
