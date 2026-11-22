import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_db_handler.dart';

/// Addon descriptor for CheckDlc expansion and downloadable content tracking.
/// Ingests into and loads from the `dlc_items` relational table.
class DlcDbHandler implements IAddonDbHandler {
  @override
  String get addonKey => 'check_dlc';

  static const List<String> supportedKeys = ['check_dlc', 'dlc'];

  @override
  List<String> get handledKeys => supportedKeys;

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    final checkDlc = (payload.addons['check_dlc'] ?? payload.addons['dlc']) as Map<String, dynamic>?;
    if (checkDlc != null) {
      final dlcs = (checkDlc['dlcs'] ?? checkDlc['items']) as List?;
      if (dlcs is List) {
        batch.delete('dlc_items', where: 'game_id = ?', whereArgs: [payload.id]);
        for (final item in dlcs) {
          if (item is Map<String, dynamic>) {
            batch.insert('dlc_items', {
              'game_id': payload.id,
              'dlc_id': item['dlc_id'] as String? ?? '',
              'name': item['name'] as String? ?? '',
              'is_owned': (item['is_owned'] as bool? ?? false) ? 1 : 0,
              'price': (item['price'] is num)
                  ? (item['price'] as num).toDouble()
                  : double.tryParse(item['price']?.toString().replaceAll(RegExp(r'[^\d.]'), '') ?? ''),
              'currency': item['currency'] as String?,
              'url': item['url'] as String?,
              'image_url': item['image_url'] as String?,
            });
          }
        }
      }
    }
  }

  @override
  Future<void> delete(String gameId, Batch batch, AppDatabase database) async {
    batch.delete('dlc_items', where: 'game_id = ?', whereArgs: [gameId]);
  }

  @override
  Future<Map<String, dynamic>?> loadData(String gameId, AppDatabase database) async {
    final rows = await database.db.query(
      'dlc_items',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'id ASC',
    );
    if (rows.isEmpty) return null;
    final dlcs = rows.map((r) => {
      'dlc_id': r['dlc_id'] as String? ?? '',
      'name': r['name'] as String? ?? '',
      'is_owned': (r['is_owned'] as num?)?.toInt() == 1,
      'price': (r['price'] as num?)?.toDouble(),
      'currency': r['currency'] as String?,
      'url': r['url'] as String?,
      'image_url': r['image_url'] as String?,
    }).toList();
    return {
      'dlcs': dlcs,
      'items': dlcs,
    };
  }
}
