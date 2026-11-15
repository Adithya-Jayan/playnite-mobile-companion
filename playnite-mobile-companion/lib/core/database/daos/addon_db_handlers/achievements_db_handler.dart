import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_db_handler.dart';

/// Database handler that unpacks achievements from 'achievements', 'playnite_achievements',
/// or 'success_story' into the relational `achievements` SQLite table.
class AchievementsDbHandler implements IAddonDbHandler {
  @override
  String get addonKey => 'achievements';

  /// Addon keys that this handler recognizes for achievement payloads.
  static const List<String> supportedKeys = [
    'achievements',
    'playnite_achievements',
    'success_story',
  ];

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    Map<String, dynamic>? addonData;
    for (final key in supportedKeys) {
      final raw = payload.addons[key];
      if (raw is Map<String, dynamic>) {
        addonData = raw;
        break;
      }
    }

    List<dynamic>? rawAchievements;
    if (addonData != null) {
      final items = addonData['items'] ?? addonData['achievements'];
      if (items is List) {
        rawAchievements = items;
      }
    } else {
      final direct = payload.addons['achievements'];
      if (direct is List) {
        rawAchievements = direct;
      }
    }

    if (rawAchievements == null) return;

    // Delete existing achievements for this game to ensure fresh state
    batch.delete('achievements', where: 'game_id = ?', whereArgs: [payload.id]);

    for (final item in rawAchievements) {
      if (item is Map<String, dynamic>) {
        final rawIconUnlocked = (item['url_unlocked'] ??
            item['UrlUnlocked'] ??
            item['icon_unlocked'] ??
            item['ImageUnlocked'] ??
            item['icon'])?.toString();
        final rawIconLocked = (item['url_locked'] ??
            item['UrlLocked'] ??
            item['icon_locked'] ??
            item['ImageLocked'] ??
            item['icon'])?.toString();
        final isUnlocked = (item['unlocked'] == true ||
            item['is_unlocked'] == true ||
            item['unlocked'] == 1 ||
            item['is_unlocked'] == 1 ||
            item['unlocked'] == 'true' ||
            item['is_unlocked'] == 'true');
        final rawDate = (item['date_unlocked_utc'] ??
            item['date_unlocked'] ??
            item['unlock_time_utc'])?.toString();
        final dateUnlocked = (rawDate != null && rawDate.isNotEmpty)
            ? rawDate
            : (isUnlocked ? '1970-01-01T00:00:00.000Z' : null);
        final percent = (item['percent'] ??
            item['rarity_percent'] ??
            item['rarity_percentage'] ??
            item['rarity'] as num?)?.toDouble();
        final gamerScore = (item['gamerscore'] as num?)?.toDouble() ??
            (item['gamer_score'] as num?)?.toDouble() ??
            (item['gamerScore'] as num?)?.toDouble();
        final isHidden = (item['is_hidden'] as bool? ??
            item['isHidden'] as bool? ??
            false);

        batch.insert('achievements', {
          'game_id': payload.id,
          'api_name': item['api_name'] as String? ?? item['apiName'] as String? ?? '',
          'name': item['name'] as String? ?? '',
          'description': item['description'] as String?,
          'url_unlocked': rawIconUnlocked,
          'url_locked': rawIconLocked,
          'date_unlocked_utc': dateUnlocked,
          'percent': percent,
          'gamer_score': gamerScore,
          'is_hidden': isHidden ? 1 : 0,
        });
      }
    }
  }
}
