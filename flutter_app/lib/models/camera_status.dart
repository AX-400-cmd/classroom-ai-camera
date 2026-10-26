/// 教师目标的跟踪状态，对应后端 target_status_code。
library;

import 'dart:ui';

enum TargetStatus { none, tracking, lost }

TargetStatus parseTargetStatus(String? code) {
  switch (code) {
    case 'tracking':
      return TargetStatus.tracking;
    case 'lost':
      return TargetStatus.lost;
    default:
      return TargetStatus.none;
  }
}

/// `GET /status` 的响应模型。后端只增字段不改语义，这里对缺失字段做兜底。
class CameraStatus {
  const CameraStatus({
    required this.recording,
    required this.recordingPath,
    required this.targetStatus,
    required this.targetBox,
    required this.ptzStatus,
    required this.frameWidth,
    required this.frameHeight,
    required this.targetStatusCode,
    required this.recordingName,
    required this.recordCodec,
    required this.outputDir,
    required this.serverTime,
    // --- 行为检测（后端未开启时全是默认值，老服务端也安全）---
    this.behaviorEnabled = false,
    this.behaviorRunning = false,
    this.behaviorError = '',
    this.behaviorPersons = 0,
    this.behaviorPhone = 0,
    this.behaviorSleep = 0,
    this.behaviorBoxes = const <List<dynamic>>[],
    this.alertCount = 0,
    this.alertLastId = '',
  });

  /// 行为检测是否在跑（需要服务端加 --behavior 启动）。
  final bool behaviorEnabled;
  final bool behaviorRunning;

  /// 检测模块的错误（模型没装好 / 推理异常），非空就该提示用户。
  final String behaviorError;
  final int behaviorPersons;

  /// 当前正在触发「玩手机」/「打瞌睡」的人数。
  final int behaviorPhone;
  final int behaviorSleep;

  /// 告警框 [x, y, w, h, kind, score]，APP 端自己画在原始帧上。
  final List<List<dynamic>> behaviorBoxes;
  final int alertCount;
  final String alertLastId;

  final bool recording;
  final String recordingPath;

  /// 后端给的中文状态文案，直接展示。
  final String targetStatus;

  /// 帧像素坐标的目标框 [x, y, w, h]，未选择目标时为 null。
  final List<int>? targetBox;
  final String ptzStatus;

  /// 画面原始分辨率，画框换算的必需输入。
  final int frameWidth;
  final int frameHeight;
  final TargetStatus targetStatusCode;
  final String recordingName;
  final String recordCodec;
  final String outputDir;

  /// 服务器本地时间，用来提示「手机和电脑时间不一致」这类问题。
  final String serverTime;

  /// 有了宽高才知道怎么把像素框映射到屏幕。
  bool get hasFrameSize => frameWidth > 0 && frameHeight > 0;

  Size? get frameSize => hasFrameSize ? Size(frameWidth.toDouble(), frameHeight.toDouble()) : null;

  /// 云台是否报了错。
  bool get ptzHasError => ptzStatus.contains('失败');

  /// 检测模块是否报错（模型没装好、推理异常）。
  bool get behaviorHasError => behaviorError.isNotEmpty;

  /// 当前是否有人正在触发行为。
  bool get hasActiveBehavior => behaviorPhone > 0 || behaviorSleep > 0;

  /// 注意力不集中的人数（玩手机 + 打瞌睡已合并为一种告警）。
  int get behaviorAttention => behaviorPhone + behaviorSleep;

  /// 行为检测已启用且模型就绪。
  bool get behaviorReady => behaviorEnabled && behaviorRunning && !behaviorHasError;

  factory CameraStatus.fromJson(Map<String, dynamic> json) {
    final rawBox = json['target_box'];
    List<int>? box;
    if (rawBox is List && rawBox.length >= 4) {
      box = rawBox.map((e) => (e as num).toInt()).toList(growable: false);
    }
    return CameraStatus(
      recording: json['recording'] == true,
      recordingPath: (json['recording_path'] ?? '').toString(),
      targetStatus: (json['target_status'] ?? '未选择目标').toString(),
      targetBox: box,
      ptzStatus: (json['ptz_status'] ?? '未启用').toString(),
      frameWidth: _asInt(json['frame_width']),
      frameHeight: _asInt(json['frame_height']),
      targetStatusCode: parseTargetStatus(json['target_status_code']?.toString()),
      recordingName: (json['recording_name'] ?? '').toString(),
      recordCodec: (json['record_codec'] ?? '').toString(),
      outputDir: (json['output_dir'] ?? '').toString(),
      serverTime: _fmtServerTime(json['server_time']),
      behaviorEnabled: json['behavior_enabled'] == true,
      behaviorRunning: json['behavior_running'] == true,
      behaviorError: (json['behavior_error'] ?? '').toString(),
      behaviorPersons: _asInt(json['behavior_persons']),
      behaviorPhone: _asInt(json['behavior_phone']),
      behaviorSleep: _asInt(json['behavior_sleep']),
      behaviorBoxes: _asBoxList(json['behavior_boxes']),
      alertCount: _asInt(json['alert_count']),
      alertLastId: (json['alert_last_id'] ?? '').toString(),
    );
  }

  /// 告警框数组：元素形如 [x, y, w, h, "phone", 0.82]。
  static List<List<dynamic>> _asBoxList(Object? value) {
    if (value is! List) return const <List<dynamic>>[];
    return value
        .whereType<List>()
        .map((List<dynamic> e) => List<dynamic>.of(e))
        .toList(growable: false);
  }

  /// 后端给的是浮点 epoch 秒，也可能是字符串，两种情况都要能显示。
  static String _fmtServerTime(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final DateTime t =
          DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
      String pad(int n) => n.toString().padLeft(2, '0');
      return '${t.year}-${pad(t.month)}-${pad(t.day)} '
          '${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
    }
    return value.toString();
  }
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
