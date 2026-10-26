/// 访问令牌输入对话框（后端 `--api-token` / `CLASSROOM_API_TOKEN`）。
library;

import 'package:flutter/material.dart';

/// 弹出令牌输入框。返回 null 表示用户取消；返回空串表示"清空令牌"。
Future<String?> showTokenDialog(
  BuildContext context, {
  required String initial,
  String title = '访问令牌',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => _TokenDialog(initial: initial, title: title),
  );
}

class _TokenDialog extends StatefulWidget {
  const _TokenDialog({required this.initial, required this.title});

  final String initial;
  final String title;

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  late final TextEditingController _text;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          labelText: '令牌',
          hintText: '后端未开启鉴权时留空',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _obscure ? '显示' : '隐藏',
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.of(context).pop(_text.text.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
