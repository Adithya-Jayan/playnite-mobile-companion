import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'collapsible_stats_card.dart';

class CompletionPieChart extends StatelessWidget {
  final Map<String, int> completionBreakdown;
  final bool? isExpanded;
  final ValueChanged<bool>? onToggle;

  const CompletionPieChart({
    super.key,
    required this.completionBreakdown,
    this.isExpanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (completionBreakdown.isEmpty) return const SizedBox.shrink();

    final total = completionBreakdown.values.fold<int>(0, (sum, c) => sum + c);
    if (total == 0) return const SizedBox.shrink();

    final colorMap = <String, Color>{
      'Completed': AppTheme.accentGreen,
      'Beaten': AppTheme.accentCyan,
      'Playing': AppTheme.primary,
      'Not Played': const Color(0xFF57606F),
      'Abandoned': AppTheme.accentRed,
      'Plan to Play': AppTheme.accentPurple,
      'On Hold': const Color(0xFFE58E26),
    };

    final sections = <PieChartSectionData>[];
    var colorIdx = 0;
    const fallbackPalette = [
      AppTheme.primary,
      AppTheme.accentCyan,
      AppTheme.accentGreen,
      AppTheme.accentPurple,
      Color(0xFFE58E26),
      Color(0xFF747D8C),
    ];

    completionBreakdown.forEach((status, count) {
      final color = colorMap[status] ?? fallbackPalette[colorIdx % fallbackPalette.length];
      colorIdx++;
      final pct = (count / total) * 100;

      sections.add(
        PieChartSectionData(
          color: color,
          value: count.toDouble(),
          title: pct >= 5 ? '${pct.round()}%' : '',
          radius: 28,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    });

    return CollapsibleStatsCard(
      title: 'Completion Status',
      icon: Icons.pie_chart_outline,
      iconColor: AppTheme.accentCyan,
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: SizedBox(
        height: 180,
        child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 36,
                        sectionsSpace: 2,
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: completionBreakdown.entries.map((e) {
                        final color = colorMap[e.key] ?? AppTheme.textMuted;
                        final pct = ((e.value / total) * 100).toStringAsFixed(1);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  e.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ),
                              Text(
                                '$pct% (${e.value})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
