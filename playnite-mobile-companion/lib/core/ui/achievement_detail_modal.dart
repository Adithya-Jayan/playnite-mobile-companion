import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';

/// Modal bottom sheet displaying complete details of an achievement,
/// matching Playnite desktop's achievement dialog.
class AchievementDetailModal extends StatelessWidget {
  final String name;
  final String? description;
  final String? gameName;
  final String? iconUrl;
  final bool isUnlocked;
  final String? dateUnlockedUtc;
  final double? percent;
  final double? gamerScore;
  final String? category;
  final bool isHidden;
  final VoidCallback? onViewGame;

  const AchievementDetailModal({
    super.key,
    required this.name,
    this.description,
    this.gameName,
    this.iconUrl,
    required this.isUnlocked,
    this.dateUnlockedUtc,
    this.percent,
    this.gamerScore,
    this.category,
    this.isHidden = false,
    this.onViewGame,
  });

  /// Displays the achievement detail bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String name,
    String? description,
    String? gameName,
    String? iconUrl,
    required bool isUnlocked,
    String? dateUnlockedUtc,
    double? percent,
    double? gamerScore,
    String? category,
    bool isHidden = false,
    VoidCallback? onViewGame,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AchievementDetailModal(
        name: name,
        description: description,
        gameName: gameName,
        iconUrl: iconUrl,
        isUnlocked: isUnlocked,
        dateUnlockedUtc: dateUnlockedUtc,
        percent: percent,
        gamerScore: gamerScore,
        category: category,
        isHidden: isHidden,
        onViewGame: onViewGame,
      ),
    );
  }

  String? _formatUnlockDate(String? utcString) {
    if (utcString == null || utcString.isEmpty) return null;
    try {
      final dt = DateTime.parse(utcString).toLocal();
      if (dt.year <= 1970) return null;
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return null;
    }
  }

  String _formatRarityText(double? pct) {
    if (pct == null) return 'Common';
    if (pct <= 5.0) return '${pct.toStringAsFixed(1)}% (Ultra Rare)';
    if (pct <= 15.0) return '${pct.toStringAsFixed(1)}% (Very Rare)';
    if (pct <= 30.0) return '${pct.toStringAsFixed(1)}% (Rare)';
    if (pct <= 50.0) return '${pct.toStringAsFixed(1)}% (Uncommon)';
    return '${pct.toStringAsFixed(1)}% (Common)';
  }

  Color _getRarityColor(double? pct) {
    if (pct == null) return AppTheme.textMuted;
    if (pct <= 5.0) return Colors.amber;
    if (pct <= 15.0) return AppTheme.accentPurple;
    if (pct <= 30.0) return AppTheme.accentCyan;
    if (pct <= 50.0) return AppTheme.accentGreen;
    return AppTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final unlockDateStr = _formatUnlockDate(dateUnlockedUtc);
    final rarityColor = _getRarityColor(percent);
    final rarityText = _formatRarityText(percent);
    final hasIcon = iconUrl != null && iconUrl!.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header: Icon + Name + Game Name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Achievement Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isUnlocked ? AppTheme.primaryLight : AppTheme.dividerColor,
                    width: 1.5,
                  ),
                  boxShadow: isUnlocked
                      ? [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: hasIcon
                      ? PlayniteCachedImage(
                          mediaId: iconUrl,
                          fit: BoxFit.cover,
                          placeholder: Center(
                            child: Icon(
                              isUnlocked ? Icons.emoji_events_outlined : Icons.lock,
                              color: isUnlocked ? AppTheme.textMuted : AppTheme.dividerColor,
                              size: 28,
                            ),
                          ),
                          errorWidget: Center(
                            child: Icon(
                              isUnlocked ? Icons.emoji_events : Icons.lock,
                              color: isUnlocked ? Colors.amber : AppTheme.textMuted,
                              size: 28,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            isUnlocked ? Icons.emoji_events : Icons.lock,
                            color: isUnlocked ? Colors.amber : AppTheme.textMuted,
                            size: 28,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),

              // Title & Game Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (gameName != null && gameName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        gameName!.trim(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentPurple,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Badges / Metrics Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Unlock Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? AppTheme.accentGreen.withValues(alpha: 0.15)
                      : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isUnlocked
                        ? AppTheme.accentGreen.withValues(alpha: 0.4)
                        : AppTheme.dividerColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUnlocked ? Icons.check_circle : Icons.lock,
                      size: 14,
                      color: isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isUnlocked
                          ? (unlockDateStr != null ? 'Unlocked: $unlockDateStr' : 'Unlocked')
                          : 'Locked',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Rarity Badge
              if (percent != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: rarityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: rarityColor.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 14, color: rarityColor),
                      const SizedBox(width: 5),
                      Text(
                        rarityText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: rarityColor,
                        ),
                      ),
                    ],
                  ),
                ),

              // Gamerscore / Points Badge
              if (gamerScore != null && gamerScore! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        '${gamerScore!.toInt()} pts',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),

              // Category Badge
              if (category != null && category!.isNotEmpty && category != 'Default')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Text(
                    category!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Description Section
          const Text(
            'DESCRIPTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (description != null && description!.trim().isNotEmpty)
                ? description!.trim()
                : (isHidden && !isUnlocked
                    ? 'Hidden achievement. Details will be revealed once unlocked.'
                    : 'No description provided for this achievement.'),
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: (description != null && description!.trim().isNotEmpty)
                  ? AppTheme.textPrimary
                  : AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 24),

          // Bottom Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onViewGame != null) ...[
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onViewGame!();
                  },
                  icon: const Icon(Icons.sports_esports, size: 18),
                  label: const Text('View Game'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.surfaceLight,
                  foregroundColor: AppTheme.textPrimary,
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
