import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class PlayTimeCard extends StatelessWidget {
  final UnifiedGamePayload game;

  const PlayTimeCard({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final playtimeStr = DurationFormatter.formatSecondsToHoursMinutes(game.playtimeSeconds);
    final lastPlayed = game.lastActivityUtc != null && game.lastActivityUtc!.length >= 10
        ? game.lastActivityUtc!.substring(0, 10)
        : 'Never';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.access_time_filled,
              iconColor: AppTheme.primary,
              label: 'Playtime',
              value: playtimeStr,
            ),
            _buildDivider(),
            _buildStatItem(
              icon: Icons.replay,
              iconColor: AppTheme.accentCyan,
              label: 'Played',
              value: '${game.playCount} times',
            ),
            _buildDivider(),
            _buildStatItem(
              icon: Icons.calendar_month,
              iconColor: AppTheme.accentPurple,
              label: 'Last Played',
              value: lastPlayed,
            ),
            if (game.userScore != null || game.criticScore != null) ...[
              _buildDivider(),
              _buildStatItem(
                icon: Icons.star,
                iconColor: AppTheme.primaryLight,
                label: 'Score',
                value: '${game.userScore ?? game.criticScore}%',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 32,
      width: 1,
      color: AppTheme.dividerColor,
    );
  }
}
