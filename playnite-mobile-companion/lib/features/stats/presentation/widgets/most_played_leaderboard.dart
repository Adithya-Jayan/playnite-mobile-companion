import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';

class MostPlayedLeaderboard extends StatelessWidget {
  final List<TopPlayedGameEntry> topGames;

  const MostPlayedLeaderboard({super.key, required this.topGames});

  @override
  Widget build(BuildContext context) {
    if (topGames.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.leaderboard, color: AppTheme.accentPurple, size: 22),
                SizedBox(width: 8),
                Text(
                  'Most Played Games',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topGames.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final game = topGames[index];
                final rank = index + 1;
                final playtimeStr = DurationFormatter.formatSecondsToHoursMinutes(game.playtimeSeconds);

                Color rankColor = AppTheme.textMuted;
                if (rank == 1) rankColor = const Color(0xFFFFD700); // Gold
                if (rank == 2) rankColor = const Color(0xFFC0C0C0); // Silver
                if (rank == 3) rankColor = const Color(0xFFCD7F32); // Bronze

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: rankColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 32,
                          height: 44,
                          child: (game.coverDriveFileId != null && game.coverDriveFileId!.isNotEmpty)
                              ? Image.network(
                                  MediaUrlResolver.getDriveThumbnailUrl(game.coverDriveFileId!, width: 100),
                                  headers: MediaUrlResolver.getAuthHeaders(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    game.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  trailing: Text(
                    playtimeStr,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.surfaceLight,
      child: const Center(
        child: Icon(Icons.sports_esports, size: 16, color: Colors.white24),
      ),
    );
  }
}
