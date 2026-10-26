/// 课堂统计聚合数据（来自后端 `GET /stats` 的 summary 字段）。
///
/// 后端 [StatsStore.summary] 实时聚合 SQLite 落盘的告警与人数采样，
/// 这里只负责把 JSON 翻译成强类型对象，便于页面消费。
library;

class ClassStats {
  const ClassStats({
    required this.range,
    required this.alertTotal,
    required this.alertTotalSeconds,
    required this.byDetail,
    required this.byHour,
    required this.personsMax,
    required this.personsAvg,
    required this.attentionAvg,
    required this.topHour,
    required this.sampleCount,
  });

  /// 统计区间：day | week | all
  final String range;

  /// 告警总条数
  final int alertTotal;

  /// 告警累计时长（秒）
  final double alertTotalSeconds;

  /// 按行为细分的数量：phone / sleep / attention
  final Map<String, int> byDetail;

  /// 24 小时告警分布（索引 0..23 对应 0 点..23 点）
  final List<int> byHour;

  /// 到课人数峰值（统计区间内画面人数最大值）
  final int personsMax;

  /// 平均画面人数（统计区间内 persons 采样均值）
  final double personsAvg;

  /// 平均注意力人数（统计区间内 attention=玩手机+瞌睡 采样均值）
  final double attentionAvg;

  /// 最易分心时段（小时，无告警时为 -1）
  final int topHour;

  /// 人数采样条数
  final int sampleCount;

  factory ClassStats.fromJson(Map<String, dynamic> json) {
    final List<int> hour = <int>[];
    final Object? rawHour = json['by_hour'];
    if (rawHour is List) {
      for (final Object? e in rawHour) {
        if (e is int) {
          hour.add(e);
        } else if (e != null) {
          hour.add(int.tryParse(e.toString()) ?? 0);
        } else {
          hour.add(0);
        }
      }
    }
    while (hour.length < 24) {
      hour.add(0);
    }

    final Map<String, int> detail = <String, int>{};
    final Object? rawDetail = json['by_detail'];
    if (rawDetail is Map) {
      rawDetail.forEach((Object? key, Object? value) {
        final String k = key.toString();
        final int v = value is int
            ? value
            : int.tryParse(value.toString()) ?? 0;
        detail[k] = v;
      });
    }

    final String rangeRaw = json['range'].toString();
    final bool rangeOk = rangeRaw == 'day' ||
        rangeRaw == 'week' ||
        rangeRaw == 'all';

    return ClassStats(
      range: rangeOk ? rangeRaw : 'day',
      alertTotal: _toInt(json['alert_total']),
      alertTotalSeconds: _toDouble(json['alert_total_seconds']),
      byDetail: detail,
      byHour: hour,
      personsMax: _toInt(json['persons_max']),
      personsAvg: _toDouble(json['persons_avg']),
      attentionAvg: _toDouble(json['attention_avg']),
      topHour: _toInt(json['top_hour']),
      sampleCount: _toInt(json['sample_count']),
    );
  }

  int get phoneCount => byDetail['phone'] ?? 0;

  int get sleepCount => byDetail['sleep'] ?? 0;

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _toDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
