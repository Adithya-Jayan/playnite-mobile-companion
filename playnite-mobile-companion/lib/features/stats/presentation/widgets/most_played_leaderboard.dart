import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'collapsible_stats_card.dart';

class MostPlayedLeaderboard extends StatelessWidget {
  final List<TopPlayedGameEntry> topGames;
  final bool? isExpanded;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<String>? onGameTap;

  const MostPlayedLeaderboard({
    super.key,
    required this.topGames,
    this.isExpanded,
    this.onToggle,
    this.onGameTap,
  });

  @override
  Widget build(BuildContext context) {
    if (topGames.isEmpty) return const SizedBox.shrink();

    return CollapsibleStatsCard(
      title: 'Most Played Games',
      icon: Icons.leaderboard,
      iconColor: AppTheme.accentPurple,
      badge: 'Top ${topGames.length}',
      isExpanded: isExpanded,
      onToggle: onToggle,
      child: ListView.separated(
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
                  onTap: onGameTap != null ? () => onGameTap!(game.gameId) : null,
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
                          child: PlayniteCachedImage(
                            mediaId: game.coverDriveFileId,
                            fit: BoxFit.cover,
                            memCacheWidth: 96,
                            memCacheHeight: 132,
                            placeholder: _buildPlaceholder(),
                            errorWidget: _buildPlaceholder(),
                          ),
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
