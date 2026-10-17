import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/drive_api_service.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef SyncProgressCallback = void Function(SyncProgress progress);

/// Core Delta Pull Engine orchestrating incremental synchronization from remote storage into SQLite.
class DeltaPullManager {
  final DriveApiService driveService;
  final AppDatabase database;
  late final GameDao gameDao;
  late final SyncMetaDao syncMetaDao;

  DeltaPullManager({
    required this.driveService,
    required this.database,
    GameDao? gameDao,
    SyncMetaDao? syncMetaDao,
  }) {
    this.gameDao = gameDao ?? GameDao(database);
    this.syncMetaDao = syncMetaDao ?? SyncMetaDao(database);
  }

  /// Computes the exact delta between the remote index and the local metadata.
  PullDiff computeDiff(SyncIndex remoteIndex, Map<String, LocalSyncEntry> localMap) {
    final toDownload = <IndexEntry>[];
    var totalBytes = 0;

    for (final entry in remoteIndex.entries.values) {
      // Synchronize manifest and game metadata JSON payloads.
      // Media assets (covers, microtrailers) are downloaded on-demand / viewport-driven.
      if (entry.category != 'game_metadata' && entry.category != 'manifest') {
        continue;
      }

      final local = localMap[entry.relativePath];
      if (local == null || local.sha256 != entry.sha256) {
        toDownload.add(entry);
        totalBytes += entry.sizeBytes;
      }
    }

    final remotePaths = remoteIndex.entries.keys.toSet();
    final toDelete = localMap.keys
        .where((path) => path.startsWith('games/') && !remotePaths.contains(path))
        .toList();

    return PullDiff(
      toDownload: toDownload,
      toDelete: toDelete,
      totalDownloadBytes: totalBytes,
    );
  }

  /// Executes an atomic, incremental delta pull with rollback safety.
  Future<SyncReport> executeDeltaPull({
    SyncProgressCallback? onProgress,
    int concurrency = 4,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Fetch remote sync_index.json
      onProgress?.call(const SyncProgress(
        phase: SyncPhase.fetchingIndex,
        current: 0,
        total: 1,
        currentItem: 'sync_index.json',
        message: 'Fetching remote sync index...',
      ));
      final remoteIndex = await driveService.fetchSyncIndex();

      // 2. Query local sync metadata & compute diff
      onProgress?.call(const SyncProgress(
        phase: SyncPhase.computingDiff,
        current: 0,
        total: 1,
        currentItem: 'sync_index.json',
        message: 'Diffing library state...',
      ));
      final localEntries = await syncMetaDao.getAllEntriesMap();
      final diff = computeDiff(remoteIndex, localEntries);

      // Fast-path: 0 downloads needed!
      if (diff.isNoOp) {
        stopwatch.stop();
        onProgress?.call(const SyncProgress(
          phase: SyncPhase.completed,
          current: 0,
          total: 0,
          message: 'Library is completely up-to-date (0 changes).',
        ));
        return SyncReport.noOp(durationMs: stopwatch.elapsedMilliseconds);
      }

      // 3. Download changed JSON payloads in parallel
      onProgress?.call(SyncProgress(
        phase: SyncPhase.downloadingPayloads,
        current: 0,
        total: diff.toDownload.length,
        totalBytes: diff.totalDownloadBytes,
        message: 'Pulling delta: ${diff.toDownload.length} payloads (${diff.totalDownloadBytes} bytes)...',
      ));

      final downloadedGames = <UnifiedGamePayload>[];
      Map<String, dynamic>? downloadedManifest;
      var bytesDownloaded = 0;
      var completedCount = 0;

      // Process downloads with bounded concurrency
      for (var i = 0; i < diff.toDownload.length; i += concurrency) {
        final end = (i + concurrency < diff.toDownload.length) ? i + concurrency : diff.toDownload.length;
        final chunk = diff.toDownload.sublist(i, end);

        final chunkFutures = chunk.map((entry) async {
          final fileIdentifier = entry.driveFileId.isNotEmpty ? entry.driveFileId : entry.relativePath;
          final jsonText = await driveService.downloadFileText(fileIdentifier);
          final dynamic parsed = jsonDecode(jsonText);

          UnifiedGamePayload? payload;
          String itemName = entry.relativePath.split('/').last;

          if (entry.category == 'manifest' && parsed is Map<String, dynamic>) {
            downloadedManifest = parsed;
            itemName = 'manifest.json';
          } else if (parsed is Map<String, dynamic>) {
            payload = UnifiedGamePayload.fromJson(parsed);
            if (payload.name.isNotEmpty) {
              itemName = payload.name;
            }
          }

          completedCount++;
          bytesDownloaded += entry.sizeBytes;

          onProgress?.call(SyncProgress(
            phase: SyncPhase.downloadingPayloads,
            current: completedCount,
            total: diff.toDownload.length,
            bytesDownloaded: bytesDownloaded,
            totalBytes: diff.totalDownloadBytes,
            message: 'Downloading $completedCount/${diff.toDownload.length} games ($itemName)...',
            currentItem: itemName,
          ));

          return payload;
        });

        final results = await Future.wait(chunkFutures);
        for (final item in results) {
          if (item != null) downloadedGames.add(item);
        }
      }

      // 4. Commit updates inside an atomic SQLite transaction
      onProgress?.call(SyncProgress(
        phase: SyncPhase.committingDatabase,
        current: downloadedGames.length,
        total: diff.toDownload.length,
        bytesDownloaded: bytesDownloaded,
        totalBytes: diff.totalDownloadBytes,
        message: 'Committing transaction to local database...',
        currentItem: 'SQLite Database',
      ));

      await database.db.transaction((txn) async {
        // Upsert games & child tables
        if (downloadedGames.isNotEmpty) {
          await gameDao.batchUpsertGames(downloadedGames, txn: txn);
        }

        // Cascade delete removed games
        if (diff.toDelete.isNotEmpty) {
          final deletedIds = diff.toDelete
              .map((path) => path.replaceAll('games/', '').replaceAll('.json', ''))
              .toList();
          await gameDao.batchDeleteGames(deletedIds, txn: txn);
          await syncMetaDao.batchDeleteEntries(diff.toDelete, txn: txn);
        }

        // Save manifest metadata if updated
        if (downloadedManifest != null) {
          await txn.insert(
            'manifest_meta',
            {
              'key': 'manifest',
              'value_json': jsonEncode(downloadedManifest),
              'updated_utc': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Upsert updated sync_entries records
        await syncMetaDao.batchUpsertEntries(diff.toDownload, txn: txn);
      });

      stopwatch.stop();
      onProgress?.call(SyncProgress(
        phase: SyncPhase.completed,
        current: downloadedGames.length,
        total: diff.toDownload.length,
        bytesDownloaded: bytesDownloaded,
        totalBytes: diff.totalDownloadBytes,
        message: 'Delta sync successfully completed in ${stopwatch.elapsedMilliseconds} ms.',
      ));

      return SyncReport(
        isSuccess: true,
        downloadedCount: downloadedGames.length,
        deletedCount: diff.toDelete.length,
        bytesTransferred: bytesDownloaded,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, stack) {
      stopwatch.stop();
      debugPrint('Delta sync failed: $e\n$stack');
      onProgress?.call(SyncProgress(
        phase: SyncPhase.error,
        message: 'Sync error: $e',
      ));
      return SyncReport.failure(e.toString(), durationMs: stopwatch.elapsedMilliseconds);
    }
  }
}
