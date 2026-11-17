import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';

class RecentAchievementsTimeline extends StatelessWidget {
  final List<RecentAchievementEntry> achievements;

  const RecentAchievementsTimeline({super.key, required this.achievements});

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(String? rawUtc) {
    final dt = _parseDate(rawUtc)?.toLocal();
    if (dt == null) {
      return rawUtc != null && rawUtc.length >= 10 ? rawUtc.substring(0, 10) : '';
    }
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today at ${DateFormat('h:mm a').format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday at ${DateFormat('h:mm a').format(dt)}';
    }
    if (dt.year == now.year) {
      return DateFormat('MMM d • h:mm a').format(dt);
    }
    return DateFormat('MMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Recent Achievements',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                Text(
                  '${achievements.length} unlocked',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: achievements.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = achievements[index];
                final dateStr = _formatDate(item.dateUnlockedUtc);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Achievement Icon or Game Cover
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 40,
                          height: 40,
                          color: AppTheme.surfaceLight,
                          child: (item.urlUnlocked != null && item.urlUnlocked!.isNotEmpty)
                              ? PlayniteCachedImage(
                                  mediaId: item.urlUnlocked,
                                  fit: BoxFit.cover,
                                  placeholder: const Center(
                                    child: Icon(Icons.emoji_events_outlined,
                                        color: AppTheme.textMuted, size: 20),
                                  ),
                                  errorWidget: const Center(
                                    child: Icon(Icons.emoji_events,
                                        color: Colors.amber, size: 20),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.emoji_events,
                                      color: Colors.amber, size: 22),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Achievement Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.gameName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accentPurple,
                              ),
                            ),
                            if (item.description != null && item.description!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.description!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Date & Metrics
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (dateStr.isNotEmpty)
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (item.gamerScore != null && item.gamerScore! > 0)
                            Text(
                              '+${item.gamerScore!.toInt()}G',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            )
                          else if (item.percent != null && item.percent! > 0)
                            Text(
                              '${item.percent!.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentGreen,
                              ),
                            ),
                        ],
                      ),
                    ],
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
