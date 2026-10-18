import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class GameDetailsTile extends StatelessWidget {
  final UnifiedGamePayload game;

  const GameDetailsTile({super.key, required this.game});

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
    final developer = game.developers.isNotEmpty ? game.developers.first.name : null;
    final playtimeStr = game.playtimeSeconds > 0
        ? DurationFormatter.formatSecondsToHoursMinutes(game.playtimeSeconds)
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover Box Art
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 65,
                  height: 90,
                  child: PlayniteCachedImage(
                    mediaId: coverId,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    memCacheHeight: 280,
                    maxWidthDiskCache: 300,
                    maxHeightDiskCache: 400,
                    placeholder: _buildPlaceholder(),
                    errorWidget: _buildPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            game.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (game.favorite)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.favorite, color: Colors.pinkAccent, size: 16),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (developer != null)
                      Text(
                        developer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    const SizedBox(height: 6),

                    // Badges row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (game.source != null)
                          _buildMiniBadge(game.source!.name, AppTheme.primary),
                        if (playtimeStr != null)
                          _buildMiniBadge(playtimeStr, AppTheme.accentCyan),
                        if (game.completionStatus != null)
                          _buildMiniBadge(game.completionStatus!.name, AppTheme.accentGreen),
                        if (game.userScore != null)
                          _buildMiniBadge('${game.userScore}%', AppTheme.primaryLight),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.surfaceLight,
      child: const Center(
        child: Icon(Icons.sports_esports, size: 28, color: Colors.white24),
      ),
    );
  }
}
