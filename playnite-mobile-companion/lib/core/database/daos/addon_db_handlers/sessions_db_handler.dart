import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_db_handler.dart';

/// Database handler and descriptor that unpacks play sessions from 'game_activity' or 'player_activities'
/// into the relational `play_sessions` SQLite table and loads them on demand.
class SessionsDbHandler implements IAddonDbHandler {
  @override
  String get addonKey => 'game_activity';

  /// Addon keys recognized for session tracking data.
  static const List<String> supportedKeys = [
    'game_activity',
    'player_activities',
  ];

  @override
  List<String> get handledKeys => supportedKeys;

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    Map<String, dynamic>? activityData;
    for (final key in handledKeys) {
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

  @override
  Future<void> delete(String gameId, Batch batch, AppDatabase database) async {
    batch.delete('play_sessions', where: 'game_id = ?', whereArgs: [gameId]);
  }

  @override
  Future<Map<String, dynamic>?> loadData(String gameId, AppDatabase database) async {
    final rows = await database.db.query(
      'play_sessions',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'date_session_utc ASC',
    );
    if (rows.isEmpty) return null;

    final sessions = rows.map((r) {
      return <String, dynamic>{
        'date_session_utc': r['date_session_utc'] as String? ?? '',
        'elapsed_seconds': (r['elapsed_seconds'] as num?)?.toInt() ?? 0,
        'action_name': r['action_name'] as String?,
      };
    }).toList();

    return {
      'sessions': sessions,
      'play_sessions': sessions,
      'items': sessions,
    };
  }
}
