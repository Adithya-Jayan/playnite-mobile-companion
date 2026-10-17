import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';

class PlatformBreakdownBar extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, int> distribution;

  const PlatformBreakdownBar({
    super.key,
    required this.title,
    required this.icon,
    required this.distribution,
  });

  @override
  Widget build(BuildContext context) {
    if (distribution.isEmpty) return const SizedBox.shrink();

    final totalSeconds = distribution.values.fold<int>(0, (sum, s) => sum + s);
    if (totalSeconds == 0) return const SizedBox.shrink();

    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primaryLight, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...sorted.take(6).map((entry) {
              final ratio = (entry.value / totalSeconds).clamp(0.01, 1.0);
              final pct = ((entry.value / totalSeconds) * 100).toStringAsFixed(1);
              final durationStr = DurationFormatter.formatSecondsToHoursMinutes(entry.value);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        Text(
                          '$durationStr ($pct%)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: AppTheme.surfaceLight,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
