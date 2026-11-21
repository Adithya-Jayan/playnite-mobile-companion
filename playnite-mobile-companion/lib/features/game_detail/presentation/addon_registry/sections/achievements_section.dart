import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/achievement_detail_modal.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/achievement_helper.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../i_addon_widget.dart';

enum AchievementSort {
  unlockDate,
  rarity,
  gamerScore,
  alphabetical,
}

List<Map<String, dynamic>> _extractAchievementsList(Map<String, dynamic> addonData) {
  final rawAchievements = addonData['items'] ?? addonData['achievements'];
  if (rawAchievements is! List) return <Map<String, dynamic>>[];
  return rawAchievements.whereType<Map<String, dynamic>>().map((raw) {
    final item = Map<String, dynamic>.from(raw);
    if (AchievementHelper.isUnlocked(item)) {
      item['unlocked'] = true;
    }
    return item;
  }).toList();
}

int _extractTotalAchievements(Map<String, dynamic> addonData, int fallbackLength) {
  return (addonData['total_count'] as num?)?.toInt() ??
      (addonData['totalCount'] as num?)?.toInt() ??
      (addonData['total'] as num?)?.toInt() ??
      fallbackLength;
}

class AchievementsSection extends StatefulWidget implements IAddonSectionWidget {
  final String _addonKey;

  const AchievementsSection({
    super.key,
    String addonKey = 'playnite_achievements',
  }) : _addonKey = addonKey;

  @override
  String get addonKey => _addonKey;

  /// Addon keys supported by achievements section.
  /// Prioritizes playnite_achievements over generic and legacy keys.
  static const List<String> supportedKeys = [
    'playnite_achievements',
    'achievements',
    'success_story',
  ];

  @override
  int get displayOrder => 10;

  @override
  String get title => 'Achievements';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    if (addonData['has_achievements'] == false) {
      return const SizedBox.shrink();
    }

    final achievements = _extractAchievementsList(addonData);
    final total = _extractTotalAchievements(addonData, achievements.length);

    if (total <= 0 || achievements.isEmpty) {
      return const SizedBox.shrink();
    }

    return _AchievementsSectionWidget(
      addonData: addonData,
      gameName: game.name,
      game: game,
    );
  }

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<AchievementsSection> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AchievementsSectionWidget extends StatefulWidget {
  final Map<String, dynamic> addonData;
  final String? gameName;
  final UnifiedGamePayload? game;

  const _AchievementsSectionWidget({
    required this.addonData,
    this.gameName,
    this.game,
  });

  @override
  State<_AchievementsSectionWidget> createState() => _AchievementsSectionWidgetState();
}

class _AchievementsSectionWidgetState extends State<_AchievementsSectionWidget> {
  late String _filter;
  bool _showAll = false;
  AchievementSort _sortOrder = AchievementSort.alphabetical;

  static bool _isAchievementUnlocked(Map<String, dynamic> a) =>
      AchievementHelper.isUnlocked(a);

  static double? _getAchievementPercent(Map<String, dynamic> a) {
    final raw = a['percent'] ?? a['rarity_percent'] ?? a['rarity_percentage'] ?? a['rarity'];
    if (raw is num) return raw.toDouble();
    return null;
  }

  @override
  void initState() {
    super.initState();
    final achievements = _extractAchievementsList(widget.addonData);

    final unlocked = (widget.addonData['unlocked_count'] as num?)?.toInt() ??
        (widget.addonData['unlocked'] as num?)?.toInt() ??
        achievements.where(_isAchievementUnlocked).length;

    // Default to "Unlocked" if unlocked >= 1, otherwise "All"
    _filter = unlocked >= 1 ? 'Unlocked' : 'All';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.addonData['has_achievements'] == false) {
      return const SizedBox.shrink();
    }

    final achievements = _extractAchievementsList(widget.addonData);
    final total = _extractTotalAchievements(widget.addonData, achievements.length);

    if (total <= 0 || achievements.isEmpty) {
      return const SizedBox.shrink();
    }

    final unlocked = (widget.addonData['unlocked_count'] as num?)?.toInt() ??
        (widget.addonData['unlocked'] as num?)?.toInt() ??
        achievements.where(_isAchievementUnlocked).length;
    final locked = (widget.addonData['locked_count'] as num?)?.toInt() ??
        (widget.addonData['locked'] as num?)?.toInt() ??
        (total - unlocked);
    final gamerscore = (widget.addonData['gamerscore_current'] as num?)?.toDouble() ??
        (widget.addonData['gamerscore'] as num?)?.toDouble() ??
        0;
    final totalGamerscore = (widget.addonData['gamerscore_total'] as num?)?.toDouble() ??
        (widget.addonData['total_gamerscore'] as num?)?.toDouble() ??
        0;

    final progress = total > 0 ? (unlocked / total) : 0.0;

    final storeUrl = widget.addonData['store_url'] as String? ??
        (widget.addonData['sources_link'] is Map
            ? (widget.addonData['sources_link']['url'] ?? widget.addonData['sources_link']['Url'])?.toString()
            : null);

    // Filter
    final filtered = achievements.where((a) {
      final isUnlocked = _isAchievementUnlocked(a);
      if (_filter == 'Unlocked') return isUnlocked;
      if (_filter == 'Locked') return !isUnlocked;
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (_sortOrder) {
        case AchievementSort.unlockDate:
          final dateA = (a['date_unlocked_utc'] ?? a['date_unlocked'] ?? a['unlock_time_utc']) as String? ?? '';
          final dateB = (b['date_unlocked_utc'] ?? b['date_unlocked'] ?? b['unlock_time_utc']) as String? ?? '';
          if (dateA.isEmpty && dateB.isNotEmpty) return 1;
          if (dateA.isNotEmpty && dateB.isEmpty) return -1;
          return dateB.compareTo(dateA);

        case AchievementSort.rarity:
          final pA = _getAchievementPercent(a) ?? 100.0;
          final pB = _getAchievementPercent(b) ?? 100.0;
          return pA.compareTo(pB);

        case AchievementSort.gamerScore:
          final gA = (a['gamerscore'] as num?)?.toDouble() ?? (a['gamer_score'] as num?)?.toDouble() ?? 0.0;
          final gB = (b['gamerscore'] as num?)?.toDouble() ?? (b['gamer_score'] as num?)?.toDouble() ?? 0.0;
          return gB.compareTo(gA);

        case AchievementSort.alphabetical:
          final nameA = a['name'] as String? ?? '';
          final nameB = b['name'] as String? ?? '';
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      }
    });

    final previewLimit = 5;
    final displayedAchievements = _showAll ? filtered : filtered.take(previewLimit).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                const Icon(Icons.emoji_events, color: AppTheme.primaryLight, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Achievements ($unlocked / $total)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                if (totalGamerscore > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.accentPurple.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '${gamerscore.round()} / ${totalGamerscore.round()} G',
                      style: const TextStyle(color: AppTheme.accentPurple, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppTheme.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? AppTheme.accentGreen : AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips & Store Link Row
            Row(
              children: [
                _buildFilterChip('All', achievements.length),
                const SizedBox(width: 8),
                _buildFilterChip('Unlocked', unlocked),
                const SizedBox(width: 8),
                _buildFilterChip('Locked', locked),
                const Spacer(),
                if (storeUrl != null && storeUrl.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18, color: AppTheme.primaryLight),
                    tooltip: 'Store Achievements',
                    onPressed: () => launchUrlString(storeUrl, mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Sort Selector Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sort: ${_getSortLabel(_sortOrder)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                DropdownButton<AchievementSort>(
                  value: _sortOrder,
                  dropdownColor: AppTheme.surfaceLight,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: AchievementSort.unlockDate, child: Text('Unlock Date', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: AchievementSort.rarity, child: Text('Rarity', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: AchievementSort.gamerScore, child: Text('GamerScore', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: AchievementSort.alphabetical, child: Text('A-Z', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _sortOrder = val);
                  },
                ),
              ],
            ),
            const Divider(height: 12),

            // List of achievements
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No achievements in this category', style: TextStyle(color: AppTheme.textMuted)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayedAchievements.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ach = displayedAchievements[index];
                  final isUnlocked = _isAchievementUnlocked(ach);
                  final name = ach['name'] as String? ?? 'Secret Achievement';
                  final desc = ach['description'] as String? ?? '';
                  final date = (ach['date_unlocked_utc'] ?? ach['date_unlocked'] ?? ach['unlock_time_utc']) as String?;
                  final rawIcon = isUnlocked
                      ? (ach['url_unlocked'] ?? ach['UrlUnlocked'] ?? ach['icon_unlocked'] ?? ach['ImageUnlocked'] ?? ach['icon'])
                      : (ach['url_locked'] ?? ach['UrlLocked'] ?? ach['icon_locked'] ?? ach['ImageLocked'] ?? ach['icon']);
                  final iconUrl = rawIcon?.toString().trim();
                  final hasIcon = iconUrl != null && iconUrl.isNotEmpty;
                  final bool noRarity = ach['no_rarity'] == true || ach['no_rarety'] == true;
                  final percent = _getAchievementPercent(ach);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                    onTap: () {
                      String? steamAppId;
                      if (widget.game != null) {
                        final src = widget.game!.source?.name.toLowerCase() ?? '';
                        final plugin = widget.game!.pluginId.toLowerCase();
                        if (src.contains('steam') ||
                            plugin == 'steam' ||
                            plugin == 'cb91aec9-6843-41f9-ab81-e81171882729') {
                          steamAppId = widget.game!.gameId;
                        }
                      }

                      AchievementDetailModal.show(
                        context,
                        name: name,
                        description: desc,
                        gameName: widget.game?.name ?? widget.gameName,
                        iconUrl: iconUrl,
                        isUnlocked: isUnlocked,
                        dateUnlockedUtc: date,
                        percent: percent,
                        gamerScore: (ach['gamerscore'] as num?)?.toDouble() ??
                            (ach['points'] as num?)?.toDouble(),
                        category: ach['category'] as String?,
                        isHidden: ach['is_hidden'] == true,
                        steamAppId: steamAppId,
                        gameLinks: widget.game?.links,
                      );
                    },
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isUnlocked ? AppTheme.primaryLight : AppTheme.dividerColor,
                          width: 1,
                        ),
                      ),
                      child: hasIcon
                          ? PlayniteCachedImage(
                              mediaId: iconUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 96,
                              memCacheHeight: 96,
                              placeholder: Icon(
                                isUnlocked ? Icons.check_circle : Icons.lock,
                                color: isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                              ),
                              errorWidget: Icon(
                                isUnlocked ? Icons.check_circle : Icons.lock,
                                color: isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                              ),
                            )
                          : Icon(
                              isUnlocked ? Icons.check_circle : Icons.lock,
                              color: isUnlocked ? AppTheme.accentGreen : AppTheme.textMuted,
                            ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isUnlocked ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                    subtitle: desc.isNotEmpty
                        ? Text(
                            desc,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildRarityBadge(isUnlocked, percent, noRarity),
                        if (date != null && date.length >= 10)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              date.substring(0, 10),
                              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

            // Show All / Collapse button
            if (filtered.length > previewLimit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    icon: Icon(
                      _showAll ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppTheme.primaryLight,
                    ),
                    label: Text(
                      _showAll
                          ? 'Collapse'
                          : 'Show All ${filtered.length} Achievements',
                      style: const TextStyle(color: AppTheme.primaryLight, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => setState(() => _showAll = !_showAll),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _filter == label;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _filter = label);
      },
    );
  }

  Widget _buildRarityBadge(bool isUnlocked, double? percent, bool noRarity) {
    if (noRarity || percent == null) {
      if (isUnlocked) {
        return const Text('Unlocked', style: TextStyle(fontSize: 11, color: AppTheme.accentGreen, fontWeight: FontWeight.w600));
      }
      return const SizedBox.shrink();
    }
    // Guard against false 0.0%
    if (percent <= 0.0) {
      if (isUnlocked) {
        return const Text('Unlocked', style: TextStyle(fontSize: 11, color: AppTheme.accentGreen, fontWeight: FontWeight.w600));
      }
      return const SizedBox.shrink();
    }

    final pctStr = '${percent.toStringAsFixed(1)}%';
    return Text(
      pctStr,
      style: const TextStyle(fontSize: 11, color: AppTheme.accentCyan, fontWeight: FontWeight.bold),
    );
  }

  String _getSortLabel(AchievementSort sort) {
    switch (sort) {
      case AchievementSort.unlockDate:
        return 'Unlock Date';
      case AchievementSort.rarity:
        return 'Rarity';
      case AchievementSort.gamerScore:
        return 'GamerScore';
      case AchievementSort.alphabetical:
        return 'A-Z';
    }
  }
}
