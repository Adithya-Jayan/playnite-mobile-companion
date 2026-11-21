import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class GameListTile extends StatelessWidget {
  final UnifiedGamePayload game;
  final RatingScoreSource? ratingScoreSource;

  const GameListTile({
    super.key,
    required this.game,
    this.ratingScoreSource,
  });

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  ({int score, String label})? _getEffectiveScore() {
    switch (ratingScoreSource) {
      case RatingScoreSource.user:
        if (game.userScore != null) return (score: game.userScore!, label: 'User Score');
        break;
      case RatingScoreSource.critic:
        if (game.criticScore != null) return (score: game.criticScore!, label: 'Critic Score');
        break;
      case RatingScoreSource.community:
        if (game.communityScore != null) return (score: game.communityScore!, label: 'Community Score');
        break;
      case RatingScoreSource.composite:
      default:
        if (game.communityScore != null) return (score: game.communityScore!, label: 'Community Score');
        if (game.criticScore != null) return (score: game.criticScore!, label: 'Critic Score');
        if (game.userScore != null) return (score: game.userScore!, label: 'User Score');
        break;
    }
    // Fallback if preferred score is null:
    if (game.communityScore != null) return (score: game.communityScore!, label: 'Community Score');
    if (game.criticScore != null) return (score: game.criticScore!, label: 'Critic Score');
    if (game.userScore != null) return (score: game.userScore!, label: 'User Score');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasIcon = game.media.iconDriveFileId != null && game.media.iconDriveFileId!.isNotEmpty;
    final mediaId = hasIcon ? game.media.iconDriveFileId : game.media.coverDriveFileId;
    final playtime = game.playtimeSeconds > 0
        ? DurationFormatter.formatSecondsToHoursMinutes(game.playtimeSeconds)
        : null;

    final subParts = <String>[];
    if (game.source != null) subParts.add(game.source!.name);
    if (playtime != null) subParts.add(playtime);
    if (game.completionStatus != null) subParts.add(game.completionStatus!.name);

    final scoreInfo = _getEffectiveScore();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(hasIcon ? 6 : 4),
        child: SizedBox(
          width: hasIcon ? 44 : 44,
          height: hasIcon ? 44 : 60,
          child: PlayniteCachedImage(
            mediaId: mediaId,
            fit: hasIcon ? BoxFit.contain : BoxFit.cover,
            memCacheWidth: 120,
            memCacheHeight: 120,
            maxWidthDiskCache: 200,
            maxHeightDiskCache: 200,
            placeholder: _buildPlaceholder(),
            errorWidget: _buildPlaceholder(),
          ),
        ),
      ),
      title: Text(
        game.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subParts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scoreInfo != null)
            Tooltip(
              message: '${scoreInfo.label}: ${scoreInfo.score}%',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      '${scoreInfo.score}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (game.favorite) ...[
            const SizedBox(width: 8),
            const Icon(Icons.favorite, color: Colors.pinkAccent, size: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.surfaceLight,
      child: const Center(
        child: Icon(Icons.sports_esports, size: 20, color: Colors.white24),
      ),
    );
  }
}
