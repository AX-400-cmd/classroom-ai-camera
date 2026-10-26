/// 连接状态机 + 摄像头指令控制。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:classroom_camera_app/core/constants.dart';
import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/camera_status.dart';
import 'package:classroom_camera_app/models/connection_phase.dart';
import 'package:classroom_camera_app/models/frame_snapshot.dart';
import 'package:classroom_camera_app/models/server_profile.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/services/storage_service.dart';
import 'package:classroom_camera_app/state/frame_notifier.dart';

/// 正在执行中的指令，用于禁用按钮、显示转圈。
enum CameraAction { none, start, stop, snapshot, clearTarget, selectTarget }

class CameraController extends ChangeNotifier {
  CameraController({ApiClient? api, StorageService? storage})
      : _api = api ?? ApiClient(),
        _storage = storage ?? StorageService();

  final ApiClient _api;
  final StorageService _storage;

  /// 帧流。UI 用 ValueListenableBuilder 订阅，避免整页重建。
  final FrameNotifier frames = FrameNotifier();

  // ---- 连接状态 ----
  ConnectionPhase _phase = ConnectionPhase.idle;
  String? _errorMessage;
  String _baseUrl = '';
  /// 当前连接使用的访问令牌（后端未开鉴权时为空串）。
  String _token = '';

  // ---- 轮询 ----
  int _pollToken = 0;
  int _statusFails = 0;
  int _frameFails = 0;
  int _reconnectAttempt = 0;

  // ---- 数据 ----
  CameraStatus? _status;

  // ---- 指令 ----
  CameraAction _pending = CameraAction.none;

  // ---- 服务器档案 ----
  List<ServerProfile> _servers = const <ServerProfile>[];
  String? _lastBaseUrl;
  bool _ready = false;

  // ---- 设置 ----
  bool _autoConnect = true;
  bool _autoReconnect = true;
  bool _drawOverlay = true;
  bool _rawFrame = true;

  // ===== 只读视图 =====
  ConnectionPhase get phase => _phase;
  String? get errorMessage => _errorMessage;
  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get hasToken => _token.isNotEmpty;
  CameraStatus? get status => _status;
  CameraAction get pending => _pending;
  bool get isBusy => _pending != CameraAction.none;
  bool get isConnected => _phase == ConnectionPhase.connected;
  List<ServerProfile> get servers => _servers;
  String? get lastBaseUrl => _lastBaseUrl;
  bool get ready => _ready;
  bool get autoConnect => _autoConnect;
  bool get autoReconnect => _autoReconnect;
  bool get drawOverlay => _drawOverlay;
  bool get rawFrame => _rawFrame;

  /// 是否正在录制（优先取本地状态，取帧前的空档也能保持按钮正确）。
  bool get recording => _status?.recording ?? false;

  ApiClient get api => _api;

  // ===== 初始化 =====
  Future<void> init() async {
    _servers = await _storage.loadServers();
    _autoConnect = await _storage.loadBool(StorageKeys.autoConnect);
    _autoReconnect =
        await _storage.loadBool(StorageKeys.autoReconnect, fallback: true);
    _drawOverlay =
        await _storage.loadBool(StorageKeys.drawOverlay, fallback: true);
    _rawFrame = await _storage.loadBool(StorageKeys.rawFrame, fallback: true);
    _lastBaseUrl = await _storage.loadLastBaseUrl();
    _ready = true;
    notifyListeners();

    // 只有存在上次地址时才自动连，避免冷启动对着一个空地址空刷。
    final String? last = _lastBaseUrl;
    if (_autoConnect && last != null && last.isNotEmpty) {
      await connect(last);
    }
  }

  // ===== 连接 =====
  /// 连接指定地址。地址非法时直接进 failed 并给出可读提示。
  ///
  /// [token] 为空时沿用该地址已保存的令牌（历史档案里带令牌就能一键连），
  /// 传了则以新值为准并写回档案。后端未开启鉴权时全程留空即可。
  Future<void> connect(String input, {String? token}) async {
    final String? url = normalizeBaseUrl(input);
    if (url == null) {
      _pollToken++;
      _phase = ConnectionPhase.failed;
      _errorMessage = '地址格式不正确，示例：http://192.168.3.3:8765';
      _status = null;
      frames.clear();
      _reconnectAttempt = 0;
      notifyListeners();
      return;
    }
    _baseUrl = url;
    _api.baseUrl = url;
    _token = (token ?? _savedTokenOf(url)).trim();
    _api.token = _token;
    _reconnectAttempt = 0;
    _statusFails = 0;
    _frameFails = 0;
    _phase = ConnectionPhase.connecting;
    _errorMessage = null;
    _status = null;
    frames.clear();
    notifyListeners();
    // 不 await：重连退避最长可达 40s+，await 会把调用方（按钮）卡死。
    unawaited(_open());
  }

  /// 断开连接并停止所有轮询。
  void disconnect() {
    _pollToken++;
    _phase = ConnectionPhase.idle;
    _errorMessage = null;
    _status = null;
    _statusFails = 0;
    _frameFails = 0;
    _reconnectAttempt = 0;
    frames.clear();
    notifyListeners();
  }

  /// 手动重试（从 failed 恢复）。
  Future<void> retry() async {
    if (_baseUrl.isEmpty) return;
    _reconnectAttempt = 0;
    _phase = ConnectionPhase.connecting;
    _errorMessage = null;
    notifyListeners();
    unawaited(_open());
  }

  /// 探测连通性 → 成功则启动轮询；失败则按退避重试。
  ///
  /// 用 while 循环而不是递归，否则重连链会一层层叠上去。
  Future<void> _open() async {
    final int token = ++_pollToken;
    while (token == _pollToken) {
      try {
        final CameraStatus s = await _api.fetchStatus();
        if (token != _pollToken) return;
        _status = s;
        _statusFails = 0;
        _frameFails = 0;
        _reconnectAttempt = 0;
        _phase = ConnectionPhase.connected;
        _errorMessage = null;
        notifyListeners();

        await _rememberServer();
        unawaited(_frameLoop(token));
        unawaited(_statusLoop(token));
        return;
      } catch (error) {
        if (token != _pollToken) return;
        if (!_autoReconnect || _reconnectAttempt >= kMaxReconnectAttempts) {
          _phase = ConnectionPhase.failed;
          _errorMessage = describeError(error,
              statusCode: error is ApiException ? error.statusCode : null);
          notifyListeners();
          return;
        }
        _phase = ConnectionPhase.reconnecting;
        _errorMessage = describeError(error,
            statusCode: error is ApiException ? error.statusCode : null);
        _reconnectAttempt++;
        notifyListeners();
        await Future<void>.delayed(_backoff(_reconnectAttempt));
      }
    }
  }

  /// 档案里该地址已保存的令牌；没有则空串（后端未开鉴权的常见情况）。
  String _savedTokenOf(String url) {
    for (final ServerProfile p in _servers) {
      if (p.baseUrl == url) return p.token;
    }
    return '';
  }

  Future<void> _rememberServer() async {
    await _storage.saveLastBaseUrl(_baseUrl);
    final ServerProfile profile = ServerProfile(
      baseUrl: _baseUrl,
      lastUsed: DateTime.now(),
      token: _token,
    );
    await _storage.upsertServer(profile);
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  Duration _backoff(int attempt) {
    final int factor = 1 << (attempt - 1).clamp(0, 10);
    final int ms = kReconnectBaseDelay.inMilliseconds * factor;
    return Duration(
        milliseconds:
            ms > kReconnectMaxDelay.inMilliseconds ? kReconnectMaxDelay.inMilliseconds : ms);
  }

  // ===== 轮询循环 =====
  /// 递归 Future.delayed 而非 Timer.periodic：慢响应时不会堆积并发请求。
  Future<void> _frameLoop(int token) async {
    while (token == _pollToken && _phase == ConnectionPhase.connected) {
      final int started = DateTime.now().millisecondsSinceEpoch;
      try {
        final FrameSnapshot snap = await _api.fetchFrame(raw: _rawFrame);
        if (token != _pollToken) return;
        _frameFails = 0;
        frames.publish(snap);
      } catch (error) {
        if (token != _pollToken) return;
        _frameFails++;
        if (_frameFails >= kFrameFailThreshold) {
          // 先用轻量的 /status 探活：服务还在响应，说明只是取帧瞬时失败
          //（Wi-Fi 抖动、摄像头偶尔卡一帧），不该反复弹「连接中断」。
          if (await _probeAlive()) {
            _frameFails = 0;
          } else {
            _breakLink(error);
            return;
          }
        }
      }
      final int elapsed = DateTime.now().millisecondsSinceEpoch - started;
      // 已经出现失败时降频，避免在弱网下继续 250ms 猛刷加重拥塞。
      final int interval = _frameFails > 0
          ? kFrameSlowInterval.inMilliseconds
          : kFrameInterval.inMilliseconds;
      final int wait = interval - elapsed;
      await Future<void>.delayed(Duration(milliseconds: wait < 0 ? 0 : wait));
    }
  }

  /// 轻量探活：只问 /status，用来区分「链路真的断了」和「取帧偶尔失败」。
  Future<bool> _probeAlive() async {
    try {
      await _api.fetchStatus();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _statusLoop(int token) async {
    while (token == _pollToken && _phase == ConnectionPhase.connected) {
      await Future<void>.delayed(kStatusInterval);
      if (token != _pollToken) return;
      try {
        final CameraStatus s = await _api.fetchStatus();
        if (token != _pollToken) return;
        _statusFails = 0;
        _status = s;
        notifyListeners();
      } catch (error) {
        if (token != _pollToken) return;
        _statusFails++;
        if (_statusFails >= kStatusFailThreshold) {
          _breakLink(error);
          return;
        }
      }
    }
  }

  /// 已连接状态下的链路中断 → 转入重连。
  void _breakLink(Object error) {
    if (!_autoReconnect) {
      _phase = ConnectionPhase.failed;
      _errorMessage = describeError(error,
          statusCode: error is ApiException ? error.statusCode : null);
      notifyListeners();
      return;
    }
    _phase = ConnectionPhase.reconnecting;
    _errorMessage = describeError(error,
        statusCode: error is ApiException ? error.statusCode : null);
    _reconnectAttempt = 0;
    notifyListeners();
    unawaited(_open());
  }

  // ===== 指令 =====
  Future<String> _run(CameraAction action, Future<String> Function() body) async {
    if (!isConnected) throw const ApiException('尚未连接到服务');
    if (_pending != CameraAction.none) throw const ApiException('上一条指令还在执行');
    _pending = action;
    notifyListeners();
    try {
      final String message = await body();
      // 指令会改变 recording / target，立刻拉一次状态，不用等下一个轮询周期。
      await _refreshStatus();
      return message;
    } finally {
      _pending = CameraAction.none;
      notifyListeners();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      _status = await _api.fetchStatus();
      _statusFails = 0;
      notifyListeners();
    } catch (_) {
      // 单条状态刷新失败不打断录制流程，交给轮询去判定断线。
    }
  }

  Future<String> startRecording() =>
      _run(CameraAction.start, () => _api.post('start'));

  Future<String> stopRecording() =>
      _run(CameraAction.stop, () => _api.post('stop'));

  Future<String> takeSnapshot() =>
      _run(CameraAction.snapshot, () => _api.post('snapshot'));

  Future<String> clearTarget() =>
      _run(CameraAction.clearTarget, () => _api.post('clear_target'));

  /// 归一化坐标点选目标。
  Future<String> selectTarget(double nx, double ny) => _run(
        CameraAction.selectTarget,
        () => _api.selectTarget(nx, ny),
      );

  // ===== 服务器档案 =====
  Future<void> addServer(String input, {String? token}) async {
    final String? url = normalizeBaseUrl(input);
    if (url == null) throw const ApiException('地址格式不正确');
    await _storage.upsertServer(
      ServerProfile(baseUrl: url, lastUsed: DateTime.now(), token: token),
    );
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  /// 修改某个地址保存的访问令牌。
  ///
  /// 若改的正是当前连接的地址，令牌立即生效（改完调用方自行 retry() 即可，
  /// 不在这里自动重连，避免在设置页里改错一次就连环弹错）。
  Future<void> setServerToken(String baseUrlOrId, String token) async {
    final String value = token.trim();
    for (int i = 0; i < _servers.length; i++) {
      if (_servers[i].baseUrl == baseUrlOrId || _servers[i].id == baseUrlOrId) {
        _servers[i] = _servers[i].copyWith(token: value);
        await _storage.upsertServer(_servers[i]);
      }
    }
    _servers = await _storage.loadServers();
    if (_baseUrl == baseUrlOrId) {
      _token = value;
      _api.token = value;
    }
    notifyListeners();
  }

  Future<void> removeServer(String id) async {
    await _storage.removeServer(id);
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  Future<void> renameServer(String id, String name) async {
    await _storage.renameServer(id, name);
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  Future<void> refreshServers() async {
    _servers = await _storage.loadServers();
    notifyListeners();
  }

  // ===== 设置 =====
  Future<void> setAutoConnect(bool value) async {
    _autoConnect = value;
    notifyListeners();
    await _storage.saveBool(StorageKeys.autoConnect, value);
  }

  Future<void> setAutoReconnect(bool value) async {
    _autoReconnect = value;
    notifyListeners();
    await _storage.saveBool(StorageKeys.autoReconnect, value);
  }

  Future<void> setDrawOverlay(bool value) async {
    _drawOverlay = value;
    // 要自己画框就必须拿原始帧，否则和服务端叠加的框重影。
    if (value) _rawFrame = true;
    notifyListeners();
    await _storage.saveBool(StorageKeys.drawOverlay, value);
    if (value) await _storage.saveBool(StorageKeys.rawFrame, true);
  }

  Future<void> setRawFrame(bool value) async {
    _rawFrame = value;
    // 用服务端叠加画面时关掉本地绘制，避免两层框。
    if (!value) _drawOverlay = false;
    notifyListeners();
    await _storage.saveBool(StorageKeys.rawFrame, value);
    if (!value) await _storage.saveBool(StorageKeys.drawOverlay, false);
  }

  @override
  void dispose() {
    _pollToken++;
    _api.dispose();
    frames.dispose();
    super.dispose();
  }
}
