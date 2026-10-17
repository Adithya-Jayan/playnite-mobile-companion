import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

class ActivitySection implements IAddonSectionWidget {
  const ActivitySection();

  @override
  String get addonKey => 'game_activity';

  @override
  int get displayOrder => 30;

  @override
  String get title => 'Game Activity';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    final rawSessions = addonData['sessions'];
    final sessions = (rawSessions is List)
        ? rawSessions.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    if (sessions.isEmpty) return const SizedBox.shrink();

    // Sort descending by date
    sessions.sort((a, b) {
      final dateA = a['date_session_utc'] as String? ?? '';
      final dateB = b['date_session_utc'] as String? ?? '';
      return dateB.compareTo(dateA);
    });

    final totalSessionSeconds = sessions.fold<int>(
      0,
      (sum, s) => sum + ((s['elapsed_seconds'] as num?)?.toInt() ?? 0),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_toggle_off, color: AppTheme.accentGreen, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Play Sessions (${sessions.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                Text(
                  DurationFormatter.formatSecondsToHoursMinutes(totalSessionSeconds),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length > 5 ? 5 : sessions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = sessions[index];
                final date = s['date_session_utc'] as String? ?? '';
                final elapsed = (s['elapsed_seconds'] as num?)?.toInt() ?? 0;
                final action = s['action_name'] as String? ?? 'Play session';

                final dateDisplay = date.length >= 16 ? date.substring(0, 16).replaceAll('T', ' ') : date;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_fill, color: AppTheme.accentGreen, size: 18),
                  title: Text(
                    dateDisplay,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  ),
                  subtitle: Text(
                    action,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      DurationFormatter.formatSecondsToHoursMinutes(elapsed),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                    ),
                  ),
                );
              },
            ),
            if (sessions.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${sessions.length - 5} earlier sessions',
                    style: const TextStyle(color: AppTheme.accentGreen, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
