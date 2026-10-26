/// 告警轮询 + 系统通知 + 未读数 + 告警设置。
///
/// 循环写法与 camera_controller 保持一致：`_token` 令牌取消 + 递归
/// `Future.delayed`，不用 `Timer.periodic`（慢响应时会堆积并发请求）。
library;

import 'package:flutter/foundation.dart';

import 'package:classroom_camera_app/core/constants.dart';
import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/alert_event.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/services/notification_service.dart';
import 'package:classroom_camera_app/services/storage_service.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class AlertController extends ChangeNotifier {
  AlertController(this._camera, {NotificationService? notify, StorageService? storage})
      : _notify = notify ?? NotificationService(),
        _storage = storage ?? StorageService();

  final CameraController _camera;
  final NotificationService _notify;
  final StorageService _storage;

  List<AlertEvent> _alerts = const <AlertEvent>[];
  String _lastId = '';
  int _unread = 0;
  String? _error;
  bool _ready = false;
  int _token = 0;
  bool _looping = false;

  // ---- 设置（三段式：字段 + getter + init 里 loadBool + setter 落盘）----
  bool _notifyEnabled = true;
  bool _soundVibration = true;
  bool _dnd = false;

  /// 端侧二次去重/节流（后端已有 60s 冷却，这里是兜底）。
  final Map<String, DateTime> _recent = <String, DateTime>{};
  final List<DateTime> _globalStamps = <DateTime>[];

  List<AlertEvent> get alerts => _alerts;
  int get unread => _unread;
  String? get error => _error;
  bool get ready => _ready;
  bool get notifyEnabled => _notifyEnabled;
  bool get soundVibration => _soundVibration;
  bool get dnd => _dnd;
  bool get hasServer => _camera.isConnected;

  /// 通知插件是否可用（初始化失败时为 false，用于 UI 提示）。
  bool get notifyReady => _notify.ready;

  /// 一行诊断（插件/权限/最近错误），排查通知问题时直接看这个。
  String get notifyStatusText => _notify.statusText;

  /// 是否需要在界面上提示「通知权限未开启」。
  bool get needNotifyPermission =>
      !kIsWeb && _notifyEnabled && !_dnd && !_notify.granted;

  /// 手动申请通知权限（UI 按钮用）。
  Future<bool> requestNotifyPermission() async {
    final bool ok = await _notify.ensurePermission();
    if (ok) notifyListeners();
    return ok;
  }

  AlertEvent? get latest => _alerts.isEmpty ? null : _alerts.last;

  /// 过滤后的列表（按时间倒序）。玩手机/打瞌睡已合并为一种告警，不再分类型过滤。
  List<AlertEvent> get visible =>
      _alerts.toList().reversed.toList(growable: false);

  Future<void> init() async {
    _notifyEnabled =
        await _storage.loadBool(StorageKeys.alertNotify, fallback: true);
    _soundVibration =
        await _storage.loadBool(StorageKeys.alertSound, fallback: true);
    _dnd = await _storage.loadBool(StorageKeys.alertDnd, fallback: false);
    _ready = true;
    notifyListeners();
    if (!kIsWeb) {
      await _notify.init();
      // 先看系统里到底开没开（用户可能已在设置里手动打开），没开再申请
      final bool enabled = await _notify.checkEnabled();
      if (!enabled && _notifyEnabled) {
        await _notify.requestPermission();
      }
      notifyListeners();
    }
    startLoop();
  }

  /// UI 进入页面时刷新通知权限状态（用户可能刚在系统设置里改过）。
  Future<void> refreshNotifyStatus() async {
    if (kIsWeb) return;
    await _notify.checkEnabled();
    notifyListeners();
  }

  /// 启动轮询。重复调用安全（token 覆盖，旧循环自然退出）。
  void startLoop() {
    if (_looping) return;
    _looping = true;
    _loop(_token);
  }

  Future<void> _loop(int token) async {
    while (token == _token) {
      await Future<void>.delayed(kAlertInterval);
      if (token != _token) return;
      await refresh();
    }
  }

  /// 增量拉一次告警。连接断开时直接返回（不报错，交给 CameraController 判定链路）。
  Future<void> refresh() async {
    if (!_camera.isConnected) return;
    try {
      final List<AlertEvent> fresh =
          await _camera.api.fetchAlerts(since: _lastId);
      // 只要服务端响应正常就清空旧错误，避免某一次失败导致横幅永久挂住。
      final bool hadError = _error != null;
      _error = null;
      if (fresh.isEmpty) {
        if (hadError) notifyListeners();
        return;
      }
      final Set<String> seen =
          _alerts.map((AlertEvent e) => e.id).toSet();
      final List<AlertEvent> added = fresh
          .where((AlertEvent e) => !seen.contains(e.id))
          .toList(growable: false);
      if (added.isEmpty) {
        if (hadError) notifyListeners();
        return;
      }
      _alerts = <AlertEvent>[..._alerts, ...added];
      _lastId = added.last.id;
      _unread += added.length;
      for (final AlertEvent e in added) {
        _maybeNotify(e);
      }
      notifyListeners();
    } catch (error) {
      // 单条告警拉取失败不打断主流程，只提示。
      _error = describeError(error,
          statusCode: error is ApiException ? error.statusCode : null);
      notifyListeners();
    }
  }

  /// 是否弹系统通知：免打扰 / 开关 / 端侧节流三重判断。
  void _maybeNotify(AlertEvent event) {
    if (kIsWeb || _dnd || !_notifyEnabled) return;
    // 测试告警（点「测试」产生）不走节流，否则点了没反应会让人以为功能坏了
    final bool isTest = event.evidence.contains('测试');
    if (!isTest) {
      if (!_globalRateOk()) return;
      final DateTime? last = _recent[event.dedupeKey];
      final DateTime now = DateTime.now();
      if (last != null && now.difference(last) < kAlertNotifyThrottle) return;
      _recent[event.dedupeKey] = now;
    }
    _notify.show(event, soundVibration: _soundVibration);
  }

  bool _globalRateOk() {
    final DateTime now = DateTime.now();
    _globalStamps.removeWhere(
        (DateTime t) => now.difference(t) > kAlertNotifyWindow);
    if (_globalStamps.length >= kAlertNotifyMaxInWindow) return false;
    _globalStamps.add(now);
    return true;
  }

  void markAllRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  /// 清空服务端告警与本地列表。
  Future<String> clear() async {
    try {
      final String message = await _camera.api.clearAlerts();
      _alerts = const <AlertEvent>[];
      _lastId = '';
      _unread = 0;
      await _notify.cancelAll();
      notifyListeners();
      return message;
    } catch (error) {
      throw ApiException(describeError(error,
          statusCode: error is ApiException ? error.statusCode : null));
    }
  }

  /// 让服务端造一条假告警，用来验证通知链路（不用真的做动作）。
  Future<String> sendTestAlert({String kind = 'phone'}) =>
      _camera.api.sendTestAlert(kind: kind);

  // ===== 设置（改内存 → notifyListeners → 落盘）=====
  Future<void> setNotifyEnabled(bool value) async {
    _notifyEnabled = value;
    notifyListeners();
    if (value && !kIsWeb) {
      await _notify.requestPermission();
    }
    await _storage.saveBool(StorageKeys.alertNotify, value);
  }

  Future<void> setSoundVibration(bool value) async {
    _soundVibration = value;
    notifyListeners();
    await _storage.saveBool(StorageKeys.alertSound, value);
  }

  Future<void> setDnd(bool value) async {
    _dnd = value;
    notifyListeners();
    await _storage.saveBool(StorageKeys.alertDnd, value);
  }

  @override
  void dispose() {
    _token++;
    _looping = false;
    super.dispose();
  }
}
