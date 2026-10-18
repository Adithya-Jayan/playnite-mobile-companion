import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class GameCardGrid extends StatelessWidget {
  final UnifiedGamePayload game;

  const GameCardGrid({super.key, required this.game});

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverId = game.media.coverDriveFileId;

    return GestureDetector(
      onTap: () {
        final bgId = game.media.backgroundDriveFileId;
        if (!_isTesting && bgId != null && bgId.isNotEmpty) {
          final isDirectHttp = bgId.startsWith('http://') || bgId.startsWith('https://');
          final streamUrl = isDirectHttp ? bgId : MediaUrlResolver.getDriveMediaStreamUrl(bgId);
          final headers = (isDirectHttp && !streamUrl.contains('googleapis.com'))
              ? <String, String>{}
              : MediaUrlResolver.getAuthHeaders();
          precacheImage(NetworkImage(streamUrl, headers: headers), context).catchError((_) {});
        }
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
              // Cover Art Image with disk cache, memory downsampling and Hero transition
              Hero(
                tag: 'cover_${game.id}',
                child: PlayniteCachedImage(
                  mediaId: coverId,
                  fit: BoxFit.cover,
                  memCacheWidth: 280,
                  memCacheHeight: 420,
                  maxWidthDiskCache: 400,
                  maxHeightDiskCache: 600,
                  placeholder: _buildPlaceholder(),
                  errorWidget: _buildPlaceholder(),
                ),
              ),

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

              // Multi-Store Copy Badge (DuplicateHider)
              if (game.otherCopies.isNotEmpty)
                Positioned(
                  top: 6,
                  left: game.isInstalled ? 26 : 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: AppTheme.primaryLight, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy_all, color: AppTheme.primaryLight, size: 9),
                        const SizedBox(width: 2),
                        Text(
                          '+${game.otherCopies.length}',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                        ),
                      ],
                    ),
                  ),
                ),

              // Hidden Game Badge
              if (game.hidden && !game.isDuplicate)
                Positioned(
                  top: 6,
                  right: game.favorite ? 28 : 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'HIDDEN',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
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
