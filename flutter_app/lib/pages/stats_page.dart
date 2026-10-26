/// 课堂统计页（底部导航第 4 个 tab）。
///
/// 数据来自后端 `GET /stats`：注意力不集中(玩手机/打瞌睡)分布、
/// 到课人数峰值、24 小时告警分布。支持日/周/全部切换、
/// 下拉刷新与 15 秒自动刷新。柱状图用纯 Flutter 绘制，不引入图表依赖。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:classroom_camera_app/core/format.dart';
import 'package:classroom_camera_app/models/class_stats.dart';
import 'package:classroom_camera_app/services/api_client.dart';
import 'package:classroom_camera_app/state/camera_controller.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  ClassStats? _stats;
  String _range = 'day';
  String? _error;
  bool _loading = false;
  Timer? _timer;

  static const Map<String, String> ranges = <String, String>{
    'day': '今日',
    'week': '近 7 天',
    'all': '全部',
  };

  @override
  void initState() {
    super.initState();
    _load();
    // IndexedStack 里始终挂载，轻量轮询即可保持数据新鲜
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final CameraController camera =
        context.read<CameraController>();
    if (!camera.isConnected) {
      setState(() => _error = '尚未连接服务');
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
      if (force) _error = null;
    });
    try {
      final ClassStats stats =
          await camera.api.fetchStats(range: _range);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(
          error,
          statusCode: error is ApiException ? error.statusCode : null,
        );
        _loading = false;
      });
    }
  }

  void _switchRange(String range) {
    if (range == _range) return;
    setState(() => _range = range);
    _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final CameraController camera =
        context.watch<CameraController>();

    if (!camera.isConnected) {
      return const _EmptyState(
        icon: Icons.link_off,
        title: '尚未连接服务',
        message: '先在「实时预览」页连上电脑，才能查看课堂统计。',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: <Widget>[
          _RangeBar(
            current: _range,
            loading: _loading,
            onSelect: _switchRange,
            onRefresh: () => _load(force: true),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            _Notice(icon: Icons.error_outline, text: _error!, isError: true),
          if (_stats == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _Body(stats: _stats!),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.current,
    required this.loading,
    required this.onSelect,
    required this.onRefresh,
  });

  final String current;
  final bool loading;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SegmentedButton<String>(
          selected: <String>{current},
          onSelectionChanged: (Set<String> sel) => onSelect(sel.first),
          segments: _StatsPageState.ranges.entries
              .map((MapEntry<String, String> e) =>
                  ButtonSegment<String>(value: e.key, label: Text(e.value)))
              .toList(),
        ),
        const Spacer(),
        IconButton(
          tooltip: '刷新',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final ClassStats stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<_Card> cards = <_Card>[
      _Card('注意力不集中', '${stats.phoneCount + stats.sleepCount}', ''),
      _Card('到课人数(峰值)', '${stats.personsMax}', '人'),
      _Card(
        '最易分心时段',
        stats.topHour >= 0 ? '${stats.topHour}:00' : '-',
        '',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: cards,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('24 小时告警分布', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                _HourBars(byHour: stats.byHour, topHour: stats.topHour),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '到课人数取统计区间内「画面人数峰值」。'
            '数据来自服务端本地数据库，重启服务不丢。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.label, this.value, this.unit);

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 24 小时柱状图，纯 Flutter 绘制（Container 高度按比例），无外部依赖。
class _HourBars extends StatelessWidget {
  const _HourBars({required this.byHour, required this.topHour});

  final List<int> byHour;
  final int topHour;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int maxVal = byHour.fold(0, (int a, int b) => b > a ? b : a);
    const double barMaxHeight = 130.0;

    return SizedBox(
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(24, (int i) {
          final int v = byHour[i];
          final double h =
              maxVal > 0 ? (v / maxVal) * barMaxHeight : 0.0;
          final bool isTop = i == topHour && v > 0;
          final bool showLabel = i % 3 == 0;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (v > 0)
                  Text(
                    '$v',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontSize: 8),
                  ),
                Container(
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isTop
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  showLabel ? '$i' : '',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
