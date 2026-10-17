import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class GameCardGrid extends StatelessWidget {
  final UnifiedGamePayload game;

  const GameCardGrid({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final coverId = game.media.coverDriveFileId;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameDetailScreen(game: game)),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            border: Border.all(color: AppTheme.dividerColor, width: 0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover Art Image
              if (coverId != null && coverId.isNotEmpty)
                Image.network(
                  MediaUrlResolver.getDriveThumbnailUrl(coverId, width: 300),
                  headers: MediaUrlResolver.getAuthHeaders(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                )
              else
                _buildPlaceholder(),

              // Gradient vignette for bottom text readability
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // Title and Playtime Overlay
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (game.playtimeSeconds > 0)
                          Text(
                            DurationFormatter.formatSecondsToHoursMinutes(game.playtimeSeconds),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryLight,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        if (game.source != null)
                          Text(
                            game.source!.name,
                            style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Favorite Heart Icon
              if (game.favorite)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 14),
                  ),
                ),

              // Installed Indicator
              if (game.isInstalled)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.surfaceLight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports_esports, color: Colors.white24, size: 36),
              const SizedBox(height: 6),
              Text(
                game.name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
