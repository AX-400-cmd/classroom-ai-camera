/// 一条行为告警，对应后端 `/alerts` 返回数组里的一个元素。
///
/// 玩手机与打瞌睡已合并成一种告警「注意力不集中」，具体表现放在 [detail] 里。
library;

/// 告警类型。合并后只有一种：注意力不集中。
enum AlertKind { attention }

AlertKind parseAlertKind(Object? value) => AlertKind.attention;

/// 具体表现（只用于展示与回看，不再区分告警类型）。
enum AlertDetail { phone, sleep, attention }

AlertDetail parseAlertDetail(Object? value) {
  switch (value?.toString()) {
    case 'phone':
      return AlertDetail.phone;
    case 'sleep':
      return AlertDetail.sleep;
    default:
      return AlertDetail.attention;
  }
}

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.kind,
    required this.trackId,
    required this.timestamp,
    required this.seconds,
    required this.box,
    required this.score,
    required this.evidence,
    required this.snapshot,
    required this.snapshotUrl,
    this.detail = AlertDetail.attention,
  });

  /// 后端形如 "a0001"，字典序即时间序，可直接当增量游标与去重键。
  final String id;
  final AlertKind kind;
  final int trackId;
  final DateTime timestamp;
  final double seconds;

  /// 帧像素框 [x, y, w, h]。
  final List<int> box;
  final double score;
  final String evidence;
  final String snapshot;
  final String snapshotUrl;

  /// 具体表现：疑似玩手机 / 疑似低头瞌睡。
  final AlertDetail detail;

  String get kindLabel => '注意力不集中';

  String get detailLabel {
    switch (detail) {
      case AlertDetail.phone:
        return '疑似玩手机';
      case AlertDetail.sleep:
        return '疑似低头瞌睡';
      case AlertDetail.attention:
        return '';
    }
  }

  /// 列表标题，例如「#3 · 注意力不集中 3.4 秒」。
  String get title =>
      '#$trackId · $kindLabel ${seconds.toStringAsFixed(1)} 秒';

  bool get hasSnapshot => snapshot.isNotEmpty;

  /// 同一个人同一类告警的端侧去重键（合并后按人去重）。
  String get dedupeKey => '${trackId}-attention';

  factory AlertEvent.fromJson(Map<String, dynamic> json) {
    final Object? rawBox = json['box'];
    final double ts = (json['ts'] as num?)?.toDouble() ?? 0;
    return AlertEvent(
      id: (json['id'] ?? '').toString(),
      kind: parseAlertKind(json['kind']),
      trackId: (json['track_id'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt()),
      seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
      box: rawBox is List
          ? rawBox
              .whereType<num>()
              .map((num e) => e.toInt())
              .toList(growable: false)
          : const <int>[],
      score: (json['score'] as num?)?.toDouble() ?? 0,
      evidence: (json['evidence'] ?? '').toString(),
      snapshot: (json['snapshot'] ?? '').toString(),
      snapshotUrl: (json['snapshot_url'] ?? '').toString(),
      detail: parseAlertDetail(json['detail']),
    );
  }
}
