import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

class HltbSection implements IAddonSectionWidget {
  const HltbSection();

  @override
  String get addonKey => 'how_long_to_beat';

  @override
  int get displayOrder => 20;

  @override
  String get title => 'HowLongToBeat';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    final mainStory = (addonData['main_story_seconds'] as num?)?.toInt() ?? 0;
    final mainExtra = (addonData['main_extra_seconds'] as num?)?.toInt() ?? 0;
    final completionist = (addonData['completionist_seconds'] as num?)?.toInt() ?? 0;

    if (mainStory <= 0 && mainExtra <= 0 && completionist <= 0) {
      return const SizedBox.shrink();
    }

    final maxVal = [mainStory, mainExtra, completionist].reduce((a, b) => a > b ? a : b);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.timer_outlined, color: AppTheme.accentCyan, size: 22),
                SizedBox(width: 8),
                Text(
                  'HowLongToBeat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (mainStory > 0)
              _buildTimeRow('Main Story', mainStory, maxVal, AppTheme.accentCyan),
            if (mainExtra > 0) ...[
              const SizedBox(height: 12),
              _buildTimeRow('Main + Extra', mainExtra, maxVal, AppTheme.primary),
            ],
            if (completionist > 0) ...[
              const SizedBox(height: 12),
              _buildTimeRow('Completionist', completionist, maxVal, AppTheme.accentPurple),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRow(String label, int seconds, int maxVal, Color color) {
    final ratio = maxVal > 0 ? (seconds / maxVal).clamp(0.05, 1.0) : 0.0;
    final formattedHours = DurationFormatter.formatSecondsToDecimalHours(seconds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            Text(
              formattedHours,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: AppTheme.surfaceLight,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
