import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';

class PlaytimeSummaryCard extends StatelessWidget {
  final LibraryStats stats;

  const PlaytimeSummaryCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final playtimeStr = DurationFormatter.formatTotalPlaytimeSummary(stats.totalPlaytimeSeconds);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.query_builder, color: AppTheme.primaryLight, size: 22),
                SizedBox(width: 8),
                Text(
                  'Total Playtime',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              playtimeStr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryLight,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem('Games', '${stats.totalGames}', Icons.sports_esports, AppTheme.accentCyan),
                _buildMetricItem('Installed', '${stats.installedCount}', Icons.download_done, AppTheme.accentGreen),
                _buildMetricItem('Favorites', '${stats.favoritesCount}', Icons.favorite, Colors.pinkAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
