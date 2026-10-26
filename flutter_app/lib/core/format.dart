/// 轻量格式化工具，避免为此引入 intl 依赖。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// 字节数转人类可读文本。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 秒数转 mm:ss。
String formatDuration(Duration d) {
  final int total = d.inSeconds;
  final int m = total ~/ 60;
  final int s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 把 "2026-09-28 19:54:20" 精简成 "09-28 19:54"，年份相同则省略。
String formatServerTime(String modified) {
  if (modified.length < 16) return modified;
  return modified.substring(5, 16);
}

/// 把网络异常翻译成用户能看懂的中文原因。
///
/// Flutter Web 上 `http` 抛出的 ClientException 信息极其贫乏（CORS 失败时只有一句
/// XMLHttpRequest error），必须自己归类，否则用户只看到"连接失败"却不知所以。
String describeError(Object error, {int? statusCode}) {
  if (error is TimeoutException) {
    return '请求超时，请确认电脑已启动服务、且手机与电脑在同一局域网';
  }
  if (error is http.ClientException) {
    final String msg = error.message.toLowerCase();
    if (msg.contains('xmlhttprequest')) {
      return '请求被浏览器拒绝：请确认服务已启动、地址端口正确（局域网 IP 需与电脑一致）';
    }
    if (msg.contains('failed host lookup') || msg.contains('socketexception')) {
      return '无法解析或连接该地址，请检查 IP 与端口';
    }
    if (msg.contains('connection refused') || msg.contains('connection failed')) {
      return '连接被拒绝，服务可能未启动或端口不对';
    }
    return '网络错误：${error.message}';
  }
  if (statusCode == 401) {
    return '访问令牌错误或缺失：该服务已开启鉴权，请填写正确的令牌';
  }
  if (statusCode == 503) return '服务已连通，但摄像头画面尚未准备好';
  if (statusCode == 404) return '接口不存在，请确认后端已更新到最新版本';
  if (statusCode == 409) return '操作被拒绝：文件可能正在录制或被占用';
  if (statusCode != null && statusCode >= 500) return '服务端错误（HTTP $statusCode）';
  return '连接失败：$error';
}
