import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';

/// Modal bottom sheet displaying complete details of an achievement,
/// matching Playnite desktop's achievement dialog with external storefront
/// and web guide links and spoiler reveal mechanics.
class AchievementDetailModal extends StatefulWidget {
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
  final String? steamAppId;
  final List<dynamic>? gameLinks;
  final VoidCallback? onViewGame;
  final ValueChanged<String>? onUrlLaunch;

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
    this.steamAppId,
    this.gameLinks,
    this.onViewGame,
    this.onUrlLaunch,
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
    String? steamAppId,
    List<dynamic>? gameLinks,
    VoidCallback? onViewGame,
    ValueChanged<String>? onUrlLaunch,
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
        steamAppId: steamAppId,
        gameLinks: gameLinks,
        onViewGame: onViewGame,
        onUrlLaunch: onUrlLaunch,
      ),
    );
  }

  @override
  State<AchievementDetailModal> createState() => _AchievementDetailModalState();
}

class _AchievementDetailModalState extends State<AchievementDetailModal> {
  bool _isSpoilerRevealed = false;

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

  String? _resolveSteamAchievementsUrl() {
    if (widget.steamAppId != null && widget.steamAppId!.trim().isNotEmpty) {
      return 'https://steamcommunity.com/stats/${widget.steamAppId!.trim()}/achievements';
    }
    if (widget.gameLinks != null) {
      final steamRegex = RegExp(r'(?:store\.steampowered\.com|steamcommunity\.com)/app/(\d+)');
      for (final link in widget.gameLinks!) {
        final url = _extractLinkUrl(link);
        final match = steamRegex.firstMatch(url);
        if (match != null) {
          return 'https://steamcommunity.com/stats/${match.group(1)}/achievements';
        }
      }
    }
    return null;
  }

  String _buildWebGuideSearchUrl() {
    final gName = widget.gameName?.trim() ?? '';
    final aName = widget.name.trim();
    final query = (gName.isNotEmpty ? '"$gName" "$aName" guide' : '"$aName" guide').trim();
    return 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';
  }

  String _extractLinkName(dynamic link) {
    if (link == null) return '';
    try {
      if (link is Map) return link['name']?.toString() ?? '';
      return (link.name as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  String _extractLinkUrl(dynamic link) {
    if (link == null) return '';
    try {
      if (link is Map) return link['url']?.toString() ?? '';
      return (link.url as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _launchUrl(String url) async {
    if (widget.onUrlLaunch != null) {
      widget.onUrlLaunch!(url);
      return;
    }
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch URL: $url ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlockDateStr = _formatUnlockDate(widget.dateUnlockedUtc);
    final rarityColor = _getRarityColor(widget.percent);
    final rarityText = _formatRarityText(widget.percent);
    final hasIcon = widget.iconUrl != null && widget.iconUrl!.trim().isNotEmpty;
    final steamAchievementsUrl = _resolveSteamAchievementsUrl();

    // Determine whether locked hidden achievement description should be masked
    final isMasked = widget.isHidden && !widget.isUnlocked && !_isSpoilerRevealed;

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
                    color: widget.isUnlocked ? AppTheme.primaryLight : AppTheme.dividerColor,
                    width: 1.5,
                  ),
                  boxShadow: widget.isUnlocked
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
                          mediaId: widget.iconUrl,
                          fit: BoxFit.cover,
                          placeholder: Center(
                            child: Icon(
                              widget.isUnlocked ? Icons.emoji_events_outlined : Icons.lock,
                              color: widget.isUnlocked ? AppTheme.textMuted : AppTheme.dividerColor,
                              size: 28,
                            ),
                          ),
                          errorWidget: Center(
                            child: Icon(
                              widget.isUnlocked ? Icons.emoji_events : Icons.lock,
                              color: widget.isUnlocked ? Colors.amber : AppTheme.textMuted,
                              size: 28,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            widget.isUnlocked ? Icons.emoji_events : Icons.lock,
                            color: widget.isUnlocked ? Colors.amber : AppTheme.textMuted,
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
                      widget.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (widget.gameName != null && widget.gameName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.gameName!.trim(),
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
                  color: widget.isUnlocked
                      ? AppTheme.accentGreen.withValues(alpha: 0.15)
                      : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isUnlocked
                        ? AppTheme.accentGreen.withValues(alpha: 0.4)
                        : AppTheme.dividerColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isUnlocked ? Icons.check_circle : Icons.lock,
                      size: 14,
                      color: widget.isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.isUnlocked
                          ? (unlockDateStr != null ? 'Unlocked: $unlockDateStr' : 'Unlocked')
                          : 'Locked',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Rarity Badge
              if (widget.percent != null)
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
              if (widget.gamerScore != null && widget.gamerScore! > 0)
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
                        '${widget.gamerScore!.toInt()} pts',
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
              if (widget.category != null && widget.category!.isNotEmpty && widget.category != 'Default')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Text(
                    widget.category!,
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
          const SizedBox(height: 8),

          if (isMasked)
            InkWell(
              onTap: () => setState(() => _isSpoilerRevealed = true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility_off, size: 16, color: AppTheme.accentCyan),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hidden achievement • Tap to reveal spoiler',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentCyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              (widget.description != null && widget.description!.trim().isNotEmpty)
                  ? widget.description!.trim()
                  : 'No description provided for this achievement.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: (widget.description != null && widget.description!.trim().isNotEmpty)
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
              ),
            ),
          const SizedBox(height: 16),

          // Links & Guides Section
          const Text(
            'LINKS & GUIDES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Search Guide on Web
              ActionChip(
                avatar: const Icon(Icons.search, size: 16, color: AppTheme.accentCyan),
                label: const Text('Search Guide on Web'),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                backgroundColor: AppTheme.surfaceLight,
                side: const BorderSide(color: AppTheme.dividerColor),
                onPressed: () => _launchUrl(_buildWebGuideSearchUrl()),
              ),

              // Steam Community Achievements link
              if (steamAchievementsUrl != null)
                ActionChip(
                  avatar: const Icon(Icons.open_in_new, size: 16, color: AppTheme.primaryLight),
                  label: const Text('Steam Achievements'),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: AppTheme.surfaceLight,
                  side: const BorderSide(color: AppTheme.dividerColor),
                  onPressed: () => _launchUrl(steamAchievementsUrl),
                ),

              // Relevant game links
              if (widget.gameLinks != null)
                for (final link in widget.gameLinks!) ...[
                  if (_extractLinkUrl(link).isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.link, size: 16, color: AppTheme.accentPurple),
                      label: Text(
                        _extractLinkName(link).isNotEmpty ? _extractLinkName(link) : 'Link',
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      backgroundColor: AppTheme.surfaceLight,
                      side: const BorderSide(color: AppTheme.dividerColor),
                      onPressed: () => _launchUrl(_extractLinkUrl(link)),
                    ),
                ],
            ],
          ),
          const SizedBox(height: 24),

          // Bottom Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onViewGame != null) ...[
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onViewGame!();
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
