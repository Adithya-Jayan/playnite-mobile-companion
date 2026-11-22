import 'package:sqflite/sqflite.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

/// Contract for modular database ingestion, deletion, and on-demand retrieval
/// of addon payloads using normalized child SQLite tables.
abstract class IAddonDbHandler {
  /// The canonical addon key (e.g., 'achievements', 'game_activity', 'how_long_to_beat', 'check_dlc').
  String get addonKey;

  /// Additional or legacy payload keys mapped to this handler.
  List<String> get handledKeys => [addonKey];

  /// Unpacks relevant addon data from [payload] and enqueues SQLite operations into [batch].
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database);

  /// Deletes child records for [gameId] and enqueues operations into [batch].
  Future<void> delete(String gameId, Batch batch, AppDatabase database) async {}

  /// Loads normalized relational data for [gameId] from SQLite child tables
  /// and formats it into the map expected by the UI and domain models.
  Future<Map<String, dynamic>?> loadData(String gameId, AppDatabase database) async => null;
}

/// Backwards compatibility and domain alias for Unified Addon Descriptor.
typedef AddonDescriptor = IAddonDbHandler;
