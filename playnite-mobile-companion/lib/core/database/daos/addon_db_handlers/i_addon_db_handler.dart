import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

/// Contract for modular database ingestion of addon payloads into child SQLite tables.
abstract class IAddonDbHandler {
  /// The canonical addon key (e.g., 'achievements', 'game_activity').
  String get addonKey;

  /// Unpacks relevant addon data from [payload] and enqueues SQLite operations into [batch].
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database);
}
