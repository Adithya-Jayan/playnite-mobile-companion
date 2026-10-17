import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';

class RecentActivityTimeline extends StatelessWidget {
  final List<RecentSessionEntry> sessions;

  const RecentActivityTimeline({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timeline, color: AppTheme.accentGreen, size: 22),
                SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = sessions[index];
                final durationStr = DurationFormatter.formatSecondsToHoursMinutes(s.elapsedSeconds);
                final dateStr = s.dateSessionUtc.length >= 16
                    ? s.dateSessionUtc.substring(0, 16).replaceAll('T', ' ')
                    : s.dateSessionUtc;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.videogame_asset_outlined, color: AppTheme.accentGreen, size: 20),
                  title: Text(
                    s.gameName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      durationStr,
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
}
