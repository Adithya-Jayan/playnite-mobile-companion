import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class MetadataChipsRow extends StatelessWidget {
  final UnifiedGamePayload game;

  const MetadataChipsRow({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          // Source badge
          if (game.source != null)
            _buildBadge(
              game.source!.name,
              Icons.storefront,
              AppTheme.primary,
              AppTheme.primary.withValues(alpha: 0.15),
            ),

          // Completion Status badge
          if (game.completionStatus != null)
            _buildBadge(
              game.completionStatus!.name,
              Icons.task_alt,
              AppTheme.accentGreen,
              AppTheme.accentGreen.withValues(alpha: 0.15),
            ),

          // Installed status
          if (game.isInstalled)
            _buildBadge(
              'Installed',
              Icons.download_done,
              AppTheme.accentCyan,
              AppTheme.accentCyan.withValues(alpha: 0.15),
            ),

          // Favorite badge
          if (game.favorite)
            _buildBadge(
              'Favorite',
              Icons.favorite,
              Colors.pinkAccent,
              Colors.pinkAccent.withValues(alpha: 0.15),
            ),

          // Platforms
          for (final platform in game.platforms)
            _buildChip(platform.name, Icons.devices),

          // Genres
          for (final genre in game.genres)
            _buildChip(genre.name, null),

          // Release Date
          if (game.releaseDate != null && game.releaseDate!.isNotEmpty)
            _buildChip(game.releaseDate!, Icons.event),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppTheme.textMuted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
