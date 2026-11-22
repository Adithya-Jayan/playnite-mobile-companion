import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_db_handler.dart';

/// Addon descriptor for HowLongToBeat game completion estimates.
/// Ingests into and loads from the `hltb_data` relational table.
class HltbDbHandler implements IAddonDbHandler {
  @override
  String get addonKey => 'how_long_to_beat';

  static const List<String> supportedKeys = ['how_long_to_beat', 'hltb'];

  @override
  List<String> get handledKeys => supportedKeys;

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    final hltb = (payload.addons['how_long_to_beat'] ?? payload.addons['hltb']) as Map<String, dynamic>?;
    if (hltb != null) {
      batch.insert(
        'hltb_data',
        {
          'game_id': payload.id,
          'main_story_seconds': (hltb['main_story_seconds'] as num?)?.toInt(),
          'main_extra_seconds': (hltb['main_extra_seconds'] as num?)?.toInt(),
          'completionist_seconds': (hltb['completionist_seconds'] as num?)?.toInt(),
          'all_styles_seconds': (hltb['all_styles_seconds'] as num?)?.toInt(),
          'hltb_id': hltb['hltb_id']?.toString(),
          'url': hltb['url'] as String?,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<void> delete(String gameId, Batch batch, AppDatabase database) async {
    batch.delete('hltb_data', where: 'game_id = ?', whereArgs: [gameId]);
  }

  @override
  Future<Map<String, dynamic>?> loadData(String gameId, AppDatabase database) async {
    final rows = await database.db.query(
      'hltb_data',
      where: 'game_id = ?',
      whereArgs: [gameId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'main_story_seconds': (r['main_story_seconds'] as num?)?.toInt() ?? 0,
      'main_extra_seconds': (r['main_extra_seconds'] as num?)?.toInt() ?? 0,
      'completionist_seconds': (r['completionist_seconds'] as num?)?.toInt() ?? 0,
      'all_styles_seconds': (r['all_styles_seconds'] as num?)?.toInt() ?? 0,
      'hltb_id': r['hltb_id'] as String?,
      'url': r['url'] as String?,
    };
  }
}
