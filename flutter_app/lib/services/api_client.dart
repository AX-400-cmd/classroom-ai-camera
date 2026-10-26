/// 后端 HTTP 接口封装。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:classroom_camera_app/core/constants.dart';
import 'package:classroom_camera_app/models/alert_event.dart';
import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/models/class_stats.dart';
import 'package:classroom_camera_app/models/frame_snapshot.dart';
import 'package:classroom_camera_app/models/media_file.dart';

/// 带状态码的接口异常，方便上层把 503/404/409 翻译成具体文案。
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 已规范化的服务地址，例如 `http://192.168.3.3:8765`。
  String baseUrl = '';

  /// 访问令牌（对应后端 `--api-token` / `CLASSROOM_API_TOKEN`）。
  ///
  /// 留空表示后端未开启鉴权，行为与旧版完全一致——不加任何头、不改任何 URL。
  String token = '';

  bool get hasBaseUrl => baseUrl.isNotEmpty;

  bool get hasToken => token.isNotEmpty;

  void dispose() => _client.close();

  /// 统一的鉴权头。额外头（如 Content-Type）通过 [extra] 合并进来。
  Map<String, String> _headers([Map<String, String>? extra]) {
    if (token.isEmpty && extra == null) return const <String, String>{};
    return <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?extra,
    };
  }

  /// 给"直接交给 Image / VideoPlayer 的 URL"补上令牌。
  ///
  /// 这些组件只能 GET 一个裸 URL，**无法携带请求头**，所以令牌只能走 query。
  /// 后端已支持 `?token=`，与 Authorization 头等价。
  String _withToken(String pathAndQuery) {
    if (token.isEmpty) return '$baseUrl$pathAndQuery';
    final String sep = pathAndQuery.contains('?') ? '&' : '?';
    return '$baseUrl$pathAndQuery${sep}token=${Uri.encodeComponent(token)}';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final String q = query == null || query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    return Uri.parse('$baseUrl$path$q');
  }

  /// `GET /status`
  Future<CameraStatus> fetchStatus({Duration? timeout}) async {
    final http.Response response = await _client
        .get(_uri('/status'), headers: _headers())
        .timeout(timeout ?? kStatusTimeout);
    _ensureOk(response, '获取状态');
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('状态响应格式不正确');
    }
    return CameraStatus.fromJson(decoded);
  }

  /// `GET /frame.jpg`。
  ///
  /// raw=true 时取未叠加目标框的原始帧，由 APP 自己绘制（默认）。
  Future<FrameSnapshot> fetchFrame({bool raw = true, Duration? timeout}) async {
    final http.Response response = await _client
        .get(_uri('/frame.jpg', <String, String>{
          'ts': DateTime.now().millisecondsSinceEpoch.toString(),
          if (raw) 'raw': '1',
        }), headers: _headers())
        .timeout(timeout ?? kFrameTimeout);
    if (response.statusCode == 503) {
      throw ApiException('摄像头画面尚未准备好', statusCode: response.statusCode);
    }
    _ensureOk(response, '获取画面');
    return FrameSnapshot(
      bytes: response.bodyBytes,
      frameWidth: int.tryParse(response.headers['x-frame-width'] ?? '') ?? 0,
      frameHeight: int.tryParse(response.headers['x-frame-height'] ?? '') ?? 0,
      targetBox: _parseBox(response.headers['x-target-box']),
      targetStatus: _parseStatus(response.headers['x-target-status']),
    );
  }

  /// `POST /start` `/stop` `/snapshot` `/clear_target`，返回后端 message。
  Future<String> post(String action, {Duration? timeout}) async {
    final http.Response response = await _client
        .post(_uri('/$action'), headers: _headers())
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        (data['message'] ?? '操作失败').toString(),
        statusCode: response.statusCode,
      );
    }
    return (data['message'] ?? '').toString();
  }

  /// `POST /select_target`，归一化坐标。
  Future<String> selectTarget(double x, double y, {Duration? timeout}) async {
    final http.Response response = await _client
        .post(
          _uri('/select_target'),
          headers: _headers(<String, String>{'Content-Type': 'application/json'}),
          body: jsonEncode(<String, double>{'x': x, 'y': y}),
        )
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        (data['message'] ?? '选择目标失败').toString(),
        statusCode: response.statusCode,
      );
    }
    return (data['message'] ?? '已选择目标').toString();
  }

  /// `GET /files`
  Future<List<MediaFile>> listFiles({Duration? timeout}) async {
    final http.Response response = await _client
        .get(_uri('/files'), headers: _headers())
        .timeout(timeout ?? kActionTimeout);
    _ensureOk(response, '获取文件列表');
    final Map<String, dynamic> data = _decodeJson(response);
    final Object? raw = data['files'];
    if (raw is! List) return const <MediaFile>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MediaFile.fromJson)
        .toList(growable: false);
  }

  /// `POST /files/delete`
  Future<void> deleteFile(String name, {Duration? timeout}) async {
    final http.Response response = await _client
        .post(
          _uri('/files/delete'),
          headers: _headers(<String, String>{'Content-Type': 'application/json'}),
          body: jsonEncode(<String, String>{'name': name}),
        )
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400 || data['ok'] != true) {
      throw ApiException(
        (data['message'] ?? '删除失败').toString(),
        statusCode: response.statusCode,
      );
    }
  }

  /// `GET /alerts`：增量拉取行为告警。
  ///
  /// since 为空时返回全部（受后端 history 上限约束）；否则只返回 id 更大的部分。
  Future<List<AlertEvent>> fetchAlerts({String since = '', int limit = 50,
    Duration? timeout}) async {
    final http.Response response = await _client
        .get(_uri('/alerts', <String, String>{
          if (since.isNotEmpty) 'since': since,
          'limit': '$limit',
        }), headers: _headers())
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400 || data['ok'] != true) {
      throw ApiException((data['message'] ?? '获取告警失败').toString(),
          statusCode: response.statusCode);
    }
    final Object? raw = data['alerts'];
    if (raw is! List) return const <AlertEvent>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AlertEvent.fromJson)
        .toList(growable: false);
  }

  /// `POST /alerts/clear`，返回后端 message。
  Future<String> clearAlerts({Duration? timeout}) =>
      post('alerts/clear', timeout: timeout);

  /// `GET /stats`：课堂统计聚合（日报 / 周报 / 全部）。
  ///
  /// range 取值：day | week | all。返回 [ClassStats]。
  Future<ClassStats> fetchStats(
      {String range = 'day', Duration? timeout}) async {
    final http.Response response = await _client
        .get(_uri('/stats', <String, String>{'range': range}), headers: _headers())
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400 || data['ok'] != true) {
      throw ApiException(
        (data['message'] ?? '获取课堂统计失败').toString(),
        statusCode: response.statusCode,
      );
    }
    final Object? summary = data['summary'];
    if (summary is! Map<String, dynamic>) {
      throw const ApiException('统计响应格式不正确');
    }
    return ClassStats.fromJson(summary);
  }

  /// `POST /alerts/test`：造一条假告警，用来验证通知链路而不用真的做动作。
  Future<String> sendTestAlert({String kind = 'phone', Duration? timeout}) async {
    final http.Response response = await _client
        .post(
          _uri('/alerts/test'),
          headers: _headers(<String, String>{'Content-Type': 'application/json'}),
          body: jsonEncode(<String, String>{'kind': kind}),
        )
        .timeout(timeout ?? kActionTimeout);
    final Map<String, dynamic> data = _decodeJson(response);
    if (response.statusCode >= 400 || data['ok'] != true) {
      throw ApiException((data['message'] ?? '生成测试告警失败').toString(),
          statusCode: response.statusCode);
    }
    return (data['message'] ?? '已生成测试告警').toString();
  }

  /// 告警留证截图的绝对地址（后端返回的是相对路径）。
  ///
  /// 走 `_withToken`：Image 组件无法携带请求头，令牌只能拼在 query 上。
  String alertSnapshotUrl(AlertEvent event) =>
      event.snapshotUrl.isEmpty ? '' : _withToken(event.snapshotUrl);

  /// 文件绝对地址（inline 播放 / attachment 下载）。
  String fileUrl(String name, {bool inline = true}) => _withToken(
        '/files/download?name=${Uri.encodeComponent(name)}'
        '${inline ? '' : '&disposition=attachment'}',
      );

  /// 视频封面帧绝对地址。
  String posterUrl(String name) =>
      _withToken('/files/poster?name=${Uri.encodeComponent(name)}');

  void _ensureOk(http.Response response, String action) {
    if (response.statusCode != 200) {
      throw ApiException('$action失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode);
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    final Object? decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static List<int>? _parseBox(String? header) {
    if (header == null || header.isEmpty || header == '-') return null;
    final List<int> parts = header
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList(growable: false);
    return parts.length >= 4 ? parts : null;
  }
}

TargetStatus _parseStatus(String? header) {
  switch (header) {
    case 'tracking':
      return TargetStatus.tracking;
    case 'lost':
      return TargetStatus.lost;
    default:
      return TargetStatus.none;
  }
}
