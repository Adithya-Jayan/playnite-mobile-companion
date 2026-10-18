import 'dart:math';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

enum ActivityChartMode {
  barHistogram,
  cumulativeLine,
}

class ActivitySection implements IAddonSectionWidget {
  const ActivitySection();

  @override
  String get addonKey => 'game_activity';

  @override
  int get displayOrder => 80;

  @override
  String get title => 'Play Sessions';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    return _ActivitySectionWidget(addonData: addonData);
  }
}

class _ActivitySectionWidget extends StatefulWidget {
  final Map<String, dynamic> addonData;

  const _ActivitySectionWidget({required this.addonData});

  @override
  State<_ActivitySectionWidget> createState() => _ActivitySectionWidgetState();
}

class _ActivitySectionWidgetState extends State<_ActivitySectionWidget> {
  ActivityChartMode _chartMode = ActivityChartMode.barHistogram;
  bool _showAllSessions = false;

  @override
  Widget build(BuildContext context) {
    final rawSessions = widget.addonData['sessions'];
    final sessions = (rawSessions is List)
        ? rawSessions.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    if (sessions.isEmpty) return const SizedBox.shrink();

    // Sort descending for the log list
    final recentSessions = List<Map<String, dynamic>>.from(sessions)
      ..sort((a, b) {
        final dateA = a['date_session_utc'] as String? ?? '';
        final dateB = b['date_session_utc'] as String? ?? '';
        return dateB.compareTo(dateA);
      });

    final totalSessionSeconds = sessions.fold<int>(
      0,
      (sum, s) => sum + ((s['elapsed_seconds'] as num?)?.toInt() ?? 0),
    );

    // Group by day for Bar Histogram (ascending by date)
    final Map<String, int> dailySecondsMap = {};
    for (final s in sessions) {
      final dateStr = s['date_session_utc'] as String? ?? '';
      if (dateStr.length >= 10) {
        final day = dateStr.substring(0, 10);
        final elapsed = (s['elapsed_seconds'] as num?)?.toInt() ?? 0;
        dailySecondsMap[day] = (dailySecondsMap[day] ?? 0) + elapsed;
      }
    }

    final sortedDays = dailySecondsMap.keys.toList()..sort();
    final recentDays = sortedDays.length > 20 ? sortedDays.sublist(sortedDays.length - 20) : sortedDays;
    final dailyData = recentDays.map((d) => (day: d, seconds: dailySecondsMap[d] ?? 0)).toList();

    // Cumulative points (ascending)
    final sortedAscSessions = List<Map<String, dynamic>>.from(sessions)
      ..sort((a, b) {
        final dateA = a['date_session_utc'] as String? ?? '';
        final dateB = b['date_session_utc'] as String? ?? '';
        return dateA.compareTo(dateB);
      });

    int runningSeconds = 0;
    final cumulativeData = <({String date, double cumulativeHours})>[];
    for (final s in sortedAscSessions) {
      final elapsed = (s['elapsed_seconds'] as num?)?.toInt() ?? 0;
      runningSeconds += elapsed;
      final date = (s['date_session_utc'] as String? ?? '').substring(0, min(10, (s['date_session_utc'] as String? ?? '').length));
      cumulativeData.add((date: date, cumulativeHours: runningSeconds / 3600.0));
    }

    final previewSessionsLimit = 5;
    final displayedSessions = _showAllSessions ? recentSessions : recentSessions.take(previewSessionsLimit).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                const Icon(Icons.history_toggle_off, color: AppTheme.accentGreen, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Play Sessions (${sessions.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                Text(
                  DurationFormatter.formatSecondsToHoursMinutes(totalSessionSeconds),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Segmented Button Toggle: Bar Histogram vs Cumulative Line Chart
            Center(
              child: SegmentedButton<ActivityChartMode>(
                segments: const [
                  ButtonSegment(
                    value: ActivityChartMode.barHistogram,
                    label: Text('Daily Sessions', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.bar_chart, size: 16),
                  ),
                  ButtonSegment(
                    value: ActivityChartMode.cumulativeLine,
                    label: Text('Cumulative Hours', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.show_chart, size: 16),
                  ),
                ],
                selected: {_chartMode},
                onSelectionChanged: (newSelection) {
                  setState(() => _chartMode = newSelection.first);
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Visualizer Chart Area
            Container(
              height: 140,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _chartMode == ActivityChartMode.barHistogram
                  ? _buildBarHistogram(dailyData)
                  : _buildCumulativeLineChart(cumulativeData),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Session Logs Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Session History',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                ),
                if (recentSessions.length > previewSessionsLimit)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() => _showAllSessions = !_showAllSessions),
                    child: Text(
                      _showAllSessions ? 'Collapse' : 'Show All (${recentSessions.length})',
                      style: const TextStyle(color: AppTheme.primaryLight, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),

            // Recent Sessions List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedSessions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = displayedSessions[index];
                final date = s['date_session_utc'] as String? ?? '';
                final elapsed = (s['elapsed_seconds'] as num?)?.toInt() ?? 0;
                final action = s['action_name'] as String? ?? 'Play session';
                final dateDisplay = date.length >= 16 ? date.substring(0, 16).replaceAll('T', ' ') : date;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.videogame_asset_outlined, color: AppTheme.accentGreen, size: 18),
                  title: Text(
                    dateDisplay,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    action,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      DurationFormatter.formatSecondsToHoursMinutes(elapsed),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarHistogram(List<({String day, int seconds})> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No daily session data', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
    }

    final maxSeconds = data.map((d) => d.seconds).reduce(max);
    if (maxSeconds <= 0) {
      return const Center(child: Text('No session duration recorded', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = max(6.0, (constraints.maxWidth - (data.length * 4)) / data.length);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: data.map((d) {
            final ratio = (d.seconds / maxSeconds).clamp(0.05, 1.0);
            final barHeight = ratio * (constraints.maxHeight - 24);
            final hours = (d.seconds / 3600).toStringAsFixed(1);
            final dayLabel = d.day.length >= 5 ? d.day.substring(5) : d.day;

            return Tooltip(
              message: '${d.day}: ${DurationFormatter.formatSecondsToHoursMinutes(d.seconds)}',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${hours}h',
                    style: const TextStyle(fontSize: 8, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dayLabel,
                    style: const TextStyle(fontSize: 8, color: AppTheme.textMuted),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCumulativeLineChart(List<({String date, double cumulativeHours})> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No cumulative session data', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
    }

    final maxHours = data.last.cumulativeHours > 0 ? data.last.cumulativeHours : 1.0;

    return CustomPaint(
      painter: _CumulativeLinePainter(data: data, maxHours: maxHours),
      child: const SizedBox.expand(),
    );
  }
}

class _CumulativeLinePainter extends CustomPainter {
  final List<({String date, double cumulativeHours})> data;
  final double maxHours;

  _CumulativeLinePainter({required this.data, required this.maxHours});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final linePaint = Paint()
      ..color = AppTheme.accentCyan
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.accentCyan.withValues(alpha: 0.3),
          AppTheme.accentCyan.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final stepX = data.length > 1 ? size.width / (data.length - 1) : size.width;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - ((data[i].cumulativeHours / maxHours) * (size.height - 16)) - 8;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw total hours text in top left
    final tp = TextPainter(
      text: TextSpan(
        text: 'Total: ${maxHours.toStringAsFixed(1)} hrs',
        style: const TextStyle(color: AppTheme.accentCyan, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(6, 4));
  }

  @override
  bool shouldRepaint(covariant _CumulativeLinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.maxHours != maxHours;
  }
}
