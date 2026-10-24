import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_db_handler.dart';

/// Database handler that unpacks play sessions from 'game_activity' or 'player_activities'
/// into the relational `play_sessions` SQLite table.
class SessionsDbHandler implements IAddonDbHandler {
  @override
  String get addonKey => 'game_activity';

  /// Addon keys recognized for session tracking data.
  static const List<String> supportedKeys = [
    'game_activity',
    'player_activities',
  ];

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    Map<String, dynamic>? activityData;
    for (final key in supportedKeys) {
      final raw = payload.addons[key];
      if (raw is Map<String, dynamic>) {
        activityData = raw;
        break;
      }
    }

    if (activityData == null) return;

    final rawSessions = activityData['sessions'] ?? activityData['play_sessions'] ?? activityData['items'];
    if (rawSessions is List) {
      batch.delete('play_sessions', where: 'game_id = ?', whereArgs: [payload.id]);
      for (final item in rawSessions) {
        if (item is Map<String, dynamic>) {
          batch.insert('play_sessions', {
            'game_id': payload.id,
            'date_session_utc': (item['date_session_utc'] ?? item['date_session']) as String? ?? '',
            'elapsed_seconds': (item['elapsed_seconds'] as num?)?.toInt() ?? 0,
            'action_name': item['action_name'] as String?,
          });
        }
      }
    }
  }
}
