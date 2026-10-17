import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalSyncEntry {
  final String relativePath;
  final String sha256;
  final int sizeBytes;
  final String modifiedUtc;
  final String driveFileId;
  final String mimeType;
  final String category;
  final String? gameId;
  final String lastSyncedUtc;

  const LocalSyncEntry({
    required this.relativePath,
    required this.sha256,
    required this.sizeBytes,
    required this.modifiedUtc,
    required this.driveFileId,
    required this.mimeType,
    required this.category,
    this.gameId,
    required this.lastSyncedUtc,
  });

  factory LocalSyncEntry.fromMap(Map<String, dynamic> map) {
    return LocalSyncEntry(
      relativePath: map['relative_path'] as String,
      sha256: map['sha256'] as String,
      sizeBytes: (map['size_bytes'] as num).toInt(),
      modifiedUtc: map['modified_utc'] as String,
      driveFileId: map['drive_file_id'] as String,
      mimeType: map['mime_type'] as String,
      category: map['category'] as String,
      gameId: map['game_id'] as String?,
      lastSyncedUtc: map['last_synced_utc'] as String,
    );
  }
}

class SyncMetaDao {
  final AppDatabase database;

  SyncMetaDao(this.database);

  Future<Map<String, LocalSyncEntry>> getAllEntriesMap({Transaction? txn}) async {
    final executor = txn ?? database.db;
    final rows = await executor.query('sync_entries');
    final map = <String, LocalSyncEntry>{};
    for (final row in rows) {
      final entry = LocalSyncEntry.fromMap(row);
      map[entry.relativePath] = entry;
    }
    return map;
  }

  Future<LocalSyncEntry?> getEntry(String relativePath, {Transaction? txn}) async {
    final executor = txn ?? database.db;
    final rows = await executor.query(
      'sync_entries',
      where: 'relative_path = ?',
      whereArgs: [relativePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalSyncEntry.fromMap(rows.first);
  }

  Future<void> batchUpsertEntries(List<IndexEntry> entries, {Transaction? txn}) async {
    if (entries.isEmpty) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final batch = (txn ?? database.db).batch();

    for (final entry in entries) {
      batch.insert(
        'sync_entries',
        {
          'relative_path': entry.relativePath,
          'sha256': entry.sha256,
          'size_bytes': entry.sizeBytes,
          'modified_utc': entry.modifiedUtc,
          'drive_file_id': entry.driveFileId,
          'mime_type': entry.mimeType,
          'category': entry.category,
          'game_id': entry.gameId,
          'last_synced_utc': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> batchDeleteEntries(List<String> relativePaths, {Transaction? txn}) async {
    if (relativePaths.isEmpty) return;
    final batch = (txn ?? database.db).batch();

    for (final path in relativePaths) {
      batch.delete(
        'sync_entries',
        where: 'relative_path = ?',
        whereArgs: [path],
      );
    }

    await batch.commit(noResult: true);
  }
}
