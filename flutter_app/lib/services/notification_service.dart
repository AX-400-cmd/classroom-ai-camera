/// 系统通知封装。
///
/// 两条铁律：
/// 1. 本项目仍保留 Flutter Web，Web 端没有本地通知实现，必须做平台守卫；
/// 2. 权限被拒 / 插件未初始化 / 平台通道失败时**全部静默降级**，
///    绝不把异常抛给 UI（写法参考 widgets/wakelock_sync.dart）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:classroom_camera_app/models/alert_event.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _granted = false;
  String _lastError = '';

  /// 最近一次异常原文。之前全部被 try/catch 吞掉，出问题根本没法定位。
  String get lastError => _lastError;

  /// 一行诊断，直接显示在界面上，避免靠猜排查。
  String get statusText =>
      '插件=${_ready ? '就绪' : '未就绪'}'
      ' 系统通知=${_granted ? '已开启' : '未开启'}'
      ' 最近错误=${_lastError.isEmpty ? '无' : _lastError}';

  /// 插件是否可用（Web 端、初始化失败时为 false）。
  bool get ready => _ready;

  /// 系统通知权限是否已授予（Android 13+ 未授权时 show() 会静默失败）。
  bool get granted => _granted;

  static const String channelId = 'classroom_alerts';
  static const String channelName = '课堂行为告警';
  static const String channelDescription = '学生玩手机 / 打瞌睡提醒';

  /// 同一组，避免多条告警在通知栏堆叠刷屏。
  static const String groupKey = 'com.classroom.aicamera.ALERTS';

  Future<bool> init() async {
    if (kIsWeb) return false;
    // 图标候选：首选专门的白色剪影通知图标；它在代码里只是字符串引用，
    // 可能被 AGP/R8 当无用资源移除（那样 initialize 会抛 invalid_icon），
    // 所以再兜底用 launcher 图标（Manifest 静态引用，资源名一定保留）。
    const List<String> icons = <String>[
      'ic_notification',
      '@mipmap/ic_launcher',
    ];
    for (final String icon in icons) {
      try {
        final InitializationSettings settings = InitializationSettings(
          android: AndroidInitializationSettings(icon),
        );
        await _plugin.initialize(
          settings,
          onDidReceiveNotificationResponse: _onTap,
        );
        await _createChannel();
        _ready = true;
        _lastError = '';
        return true;
      } catch (error) {
        _lastError = 'init($icon): $error';
      }
    }
    _ready = false;
    return false;
  }

  Future<void> _createChannel() async {
    await _android()?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        // 小米/澎湃OS 会把重要级别不够的通知降级成「静默通知」
        // （不弹窗、不响、只折叠在通知栏），所以这里直接给到最高
        importance: Importance.max,
        enableLights: true,
        showBadge: true,
      ),
    );
  }

  /// Android 13+ 必须动态申请，返回是否被授予。
  Future<bool> requestPermission() async {
    if (kIsWeb || !_ready) return false;
    try {
      final bool? granted =
          await _android()?.requestNotificationsPermission();
      _granted = granted ?? false;
      return _granted;
    } catch (_) {
      _granted = false;
      return false;
    }
  }

  /// 主动查询系统里通知是否已开启。
  ///
  /// 用户可能直接在系统设置里打开通知，这时 APP 从没调用过申请接口，
  /// 只看申请结果会一直误判为「未开启」，所以要以这里查到的真实状态为准。
  Future<bool> checkEnabled() async {
    if (kIsWeb || !_ready) return false;
    try {
      final bool? enabled =
          await _android()?.areNotificationsEnabled();
      _granted = enabled ?? false;
      return _granted;
    } catch (error) {
      _lastError = 'check: $error';
      return _granted;
    }
  }

  /// 供 UI 按钮调用：先查真实状态，已开直接返回 true，未开再申请。
  Future<bool> ensurePermission() async {
    if (await checkEnabled()) return true;
    return requestPermission();
  }

  Future<void> show(AlertEvent event, {bool soundVibration = true}) async {
    if (!_ready) return;
    try {
      final AndroidNotificationDetails android = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: soundVibration,
        enableVibration: soundVibration,
        // alarm 类别允许响铃+震动，避免被系统/厂商降级成静默通知
        category: AndroidNotificationCategory.alarm,
        channelShowBadge: true,
        autoCancel: true,
        onlyAlertOnce: false,
        groupKey: groupKey,
      );
      await _plugin.show(
        event.id.hashCode & 0x7fffffff, // 同一条告警不会重复弹
        event.title,
        event.evidence,
        NotificationDetails(android: android),
        payload: event.id,
      );
    } catch (error) {
      _lastError = 'show: $error';
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  AndroidFlutterLocalNotificationsPlugin? _android() => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static void _onTap(NotificationResponse response) {
    // v1：点击仅拉起 APP（launchMode=singleTop），未读清零由 AlertController 处理
  }
}
