import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

class AchievementsSection extends StatefulWidget implements IAddonSectionWidget {
  const AchievementsSection({super.key});

  @override
  String get addonKey => 'success_story';

  @override
  int get displayOrder => 10;

  @override
  String get title => 'Achievements';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    return _AchievementsSectionWidget(addonData: addonData);
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

  const _AchievementsSectionWidget({required this.addonData});

  @override
  State<_AchievementsSectionWidget> createState() => _AchievementsSectionWidgetState();
}

class _AchievementsSectionWidgetState extends State<_AchievementsSectionWidget> {
  String _filter = 'All'; // 'All', 'Unlocked', 'Locked'

  @override
  Widget build(BuildContext context) {
    final rawAchievements = widget.addonData['achievements'];
    final achievements = (rawAchievements is List)
        ? rawAchievements.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    final total = (widget.addonData['total'] as num?)?.toInt() ?? achievements.length;
    final unlocked = (widget.addonData['unlocked'] as num?)?.toInt() ??
        achievements.where((a) => a['date_unlocked_utc'] != null).length;
    final locked = (widget.addonData['locked'] as num?)?.toInt() ?? (total - unlocked);
    final gamerscore = (widget.addonData['gamerscore'] as num?)?.toDouble() ?? 0;
    final totalGamerscore = (widget.addonData['total_gamerscore'] as num?)?.toDouble() ?? 0;

    final progress = total > 0 ? (unlocked / total) : 0.0;

    final filtered = achievements.where((a) {
      final isUnlocked = a['date_unlocked_utc'] != null;
      if (_filter == 'Unlocked') return isUnlocked;
      if (_filter == 'Locked') return !isUnlocked;
      return true;
    }).toList();

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

            // Filter Chips
            Row(
              children: [
                _buildFilterChip('All', achievements.length),
                const SizedBox(width: 8),
                _buildFilterChip('Unlocked', unlocked),
                const SizedBox(width: 8),
                _buildFilterChip('Locked', locked),
              ],
            ),
            const SizedBox(height: 12),

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
                itemCount: filtered.length > 20 ? 20 : filtered.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ach = filtered[index];
                  final isUnlocked = ach['date_unlocked_utc'] != null;
                  final name = ach['name'] as String? ?? 'Secret Achievement';
                  final desc = ach['description'] as String? ?? '';
                  final date = ach['date_unlocked_utc'] as String?;
                  final iconUrl = isUnlocked ? ach['url_unlocked'] as String? : ach['url_locked'] as String?;
                  final percent = (ach['percent'] as num?)?.toDouble();

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
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
                      child: (iconUrl != null && iconUrl.startsWith('http'))
                          ? Image.network(
                              iconUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(
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
                        if (percent != null)
                          Text(
                            '${percent.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 11, color: AppTheme.accentCyan, fontWeight: FontWeight.bold),
                          ),
                        if (date != null && date.length >= 10)
                          Text(
                            date.substring(0, 10),
                            style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  );
                },
              ),
            if (filtered.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${filtered.length - 20} more achievements',
                    style: const TextStyle(color: AppTheme.primaryLight, fontSize: 12),
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
}
