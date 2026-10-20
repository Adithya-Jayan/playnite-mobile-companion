import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:playnite_mobile_companion/core/config/app_constants.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/drive_api_service.dart';
import 'package:playnite_mobile_companion/core/services/background_sync_service.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef SyncProgressCallback = void Function(SyncProgress progress);

/// Core Delta Pull Engine orchestrating incremental synchronization from remote storage into SQLite.
class DeltaPullManager {
  final DriveApiService driveService;
  final AppDatabase database;
  late final GameDao gameDao;
  late final SyncMetaDao syncMetaDao;

  bool _isCancelled = false;
  void cancel() => _isCancelled = true;
  bool get isCancelled => _isCancelled;

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
  PullDiff computeDiff(
    SyncIndex remoteIndex,
    Map<String, LocalSyncEntry> localMap, {
    MediaStorageTier mediaTier = MediaStorageTier.cacheOnly,
  }) {
    final toDownload = <IndexEntry>[];
    var totalBytes = 0;

    bool isVideoEntry(IndexEntry entry) {
      final cat = AppConstants.normalizeCategory(entry.category);
      final path = entry.relativePath.toLowerCase();
      return AppConstants.isVideoCategory(cat) ||
          path.contains('/microtrailers/') ||
          path.contains('/trailers/') ||
          path.endsWith('.mp4') ||
          path.endsWith('.webm') ||
          path.endsWith('.mkv');
    }

    bool shouldIncludeEntry(IndexEntry entry) {
      final cat = AppConstants.normalizeCategory(entry.category);
      if (cat == AppConstants.categoryGameMetadata || cat == AppConstants.categoryManifest) {
        return true;
      }
      if (mediaTier == MediaStorageTier.cacheOnly) {
        return false;
      }

      final path = entry.relativePath.toLowerCase();
      final isMedia = AppConstants.isMediaCategory(cat) ||
          isVideoEntry(entry) ||
          path.startsWith('media/');

      if (!isMedia) return false;

      if (mediaTier == MediaStorageTier.coversAndFanarts) {
        return !isVideoEntry(entry);
      }

      if (mediaTier == MediaStorageTier.completeOffline) {
        return true;
      }

      return false;
    }

    for (final entry in remoteIndex.entries.values) {
      if (!shouldIncludeEntry(entry)) {
        continue;
      }

      final cat = AppConstants.normalizeCategory(entry.category);
      final local = localMap[entry.relativePath];
      if (local == null || local.sha256 != entry.sha256) {
        toDownload.add(entry);
        totalBytes += entry.sizeBytes;
      } else if (cat != AppConstants.categoryGameMetadata && cat != AppConstants.categoryManifest) {
        // For media entries matching local database sha256, verify that the physical file
        // still exists in the local disk cache. If missing or cleared, re-download!
        final onDisk = PlayniteImageLoader.instance.getCachedFileSync(entry.driveFileId) != null ||
            PlayniteImageLoader.instance.getCachedFileSync(entry.relativePath) != null;
        if (!onDisk) {
          toDownload.add(entry);
          totalBytes += entry.sizeBytes;
        }
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
    int concurrency = 8,
    MediaStorageTier? mediaTier,
  }) async {
    final stopwatch = Stopwatch()..start();
    _isCancelled = false;
    await BackgroundSyncService.acquireWakeLock();

    try {
      // 0. Resolve active media tier from gallery settings if not explicitly passed
      final resolvedMediaTier = mediaTier ??
          (await GallerySettingsRepository(database).loadSettings()).mediaStorageTier;

      // 1. Fetch remote sync_index.json
      onProgress?.call(const SyncProgress(
        phase: SyncPhase.fetchingIndex,
        current: 0,
        total: 1,
        currentItem: 'sync_index.json',
        message: 'Fetching remote sync index...',
        stepText: 'Step 1/3: Checking Cloud Index',
      ));
      final remoteIndex = await driveService.fetchSyncIndex();
      await _recordMediaTierSizes(remoteIndex);

      // 2. Query local sync metadata & compute diff
      onProgress?.call(const SyncProgress(
        phase: SyncPhase.computingDiff,
        current: 0,
        total: 1,
        currentItem: 'sync_index.json',
        message: 'Diffing library state...',
        stepText: 'Step 1/3: Analyzing Library Changes',
      ));
      final localEntries = await syncMetaDao.getAllEntriesMap();
      final diff = computeDiff(remoteIndex, localEntries, mediaTier: resolvedMediaTier);

      // Fast-path: 0 downloads needed!
      if (diff.isNoOp) {
        await _backfillMediaDriveFileIds(remoteIndex);
        stopwatch.stop();
        onProgress?.call(const SyncProgress(
          phase: SyncPhase.completed,
          current: 0,
          total: 0,
          message: 'Library is completely up-to-date (0 changes).',
          stepText: 'Step 1/3: Complete',
        ));
        return SyncReport.noOp(durationMs: stopwatch.elapsedMilliseconds);
      }

      // 3. Download changed JSON payloads and offline media with bounded concurrency and checkpoint commits
      onProgress?.call(SyncProgress(
        phase: SyncPhase.downloadingPayloads,
        current: 0,
        total: diff.toDownload.length,
        totalBytes: diff.totalDownloadBytes,
        message: 'Pulling delta: ${diff.toDownload.length} items (${diff.totalDownloadBytes} bytes)...',
        stepText: 'Step 2/3: Downloading Payloads & Offline Media',
      ));

      final downloadedGames = <UnifiedGamePayload>[];
      final pendingGamesToCommit = <UnifiedGamePayload>[];
      final pendingEntriesToCommit = <IndexEntry>[];
      const commitBatchSize = 25;

      Map<String, dynamic>? downloadedManifest;
      var bytesDownloaded = 0;
      var completedCount = 0;

      final downloadStopwatch = Stopwatch()..start();
      double smoothedEtaSeconds = -1;

      // Process downloads using a continuous worker pool for maximum network throughput
      var nextIndex = 0;
      final totalItems = diff.toDownload.length;
      final poolConcurrency = math.min(concurrency, totalItems);

      Future<void> worker() async {
        while (!_isCancelled) {
          if (nextIndex >= totalItems) {
            break;
          }
          final index = nextIndex++;
          final entry = diff.toDownload[index];
          final fileIdentifier = entry.driveFileId.isNotEmpty ? entry.driveFileId : entry.relativePath;
          final cat = AppConstants.normalizeCategory(entry.category);
          final isMetadataOrManifest = cat == AppConstants.categoryManifest || cat == AppConstants.categoryGameMetadata;

          UnifiedGamePayload? payload;
          String itemName = entry.relativePath.split('/').last;

          try {
            if (isMetadataOrManifest) {
              final jsonText = await driveService.downloadFileText(fileIdentifier);
              final dynamic parsed = jsonDecode(jsonText);

              if (cat == AppConstants.categoryManifest && parsed is Map<String, dynamic>) {
                downloadedManifest = parsed;
                itemName = 'manifest.json';
              } else if (parsed is Map<String, dynamic>) {
                final rawPayload = UnifiedGamePayload.fromJson(parsed);

                // Resolve Drive File IDs from remoteIndex.entries for all media pointers
                final media = rawPayload.media;
                String? resolveMediaId(String? relPath, String? sha256, String? existingId) {
                  if (existingId != null && existingId.isNotEmpty) {
                    return existingId;
                  }
                  if (relPath != null && relPath.isNotEmpty) {
                    final match = remoteIndex.entries[relPath];
                    if (match != null && match.driveFileId.isNotEmpty) {
                      return match.driveFileId;
                    }
                  }
                  if (sha256 != null && sha256.isNotEmpty) {
                    final match = remoteIndex.entries.values.firstWhere(
                      (e) => e.sha256 == sha256 && e.driveFileId.isNotEmpty,
                      orElse: () => const IndexEntry(
                        relativePath: '',
                        sha256: '',
                        sizeBytes: 0,
                        modifiedUtc: '',
                        driveFileId: '',
                        mimeType: '',
                        category: '',
                      ),
                    );
                    if (match.driveFileId.isNotEmpty) {
                      return match.driveFileId;
                    }
                  }
                  return relPath;
                }

                final resolvedMedia = media.copyWith(
                  coverDriveFileId: resolveMediaId(media.coverRelativePath, media.coverSha256, media.coverDriveFileId),
                  backgroundDriveFileId: resolveMediaId(media.backgroundRelativePath, media.backgroundSha256, media.backgroundDriveFileId),
                  iconDriveFileId: resolveMediaId(media.iconRelativePath, media.iconSha256, media.iconDriveFileId),
                  logoDriveFileId: remoteIndex.entries['media/logos/${rawPayload.id}.png']?.driveFileId ??
                      media.logoDriveFileId,
                  microtrailerDriveFileId: remoteIndex.entries['media/microtrailers/${rawPayload.id}.mp4']?.driveFileId ??
                      media.microtrailerDriveFileId,
                  trailerDriveFileId: remoteIndex.entries['media/trailers/${rawPayload.id}.mp4']?.driveFileId ??
                      media.trailerDriveFileId,
                );

                payload = rawPayload.copyWith(media: resolvedMedia);
                if (payload.name.isNotEmpty) {
                  itemName = payload.name;
                }
              }
            } else {
              // Binary media payload (cover, background, icon, logo, microtrailer, trailer)
              final bytes = await driveService.downloadFileBytes(fileIdentifier);
              if (bytes.isNotEmpty) {
                final aliases = <String>[entry.relativePath];
                if (entry.driveFileId.isNotEmpty) aliases.add(entry.driveFileId);
                if (entry.sha256.isNotEmpty) aliases.add(entry.sha256);
                await PlayniteImageLoader.instance.saveToCache(
                  keyOrMediaId: entry.driveFileId.isNotEmpty ? entry.driveFileId : entry.relativePath,
                  bytes: bytes,
                  aliases: aliases,
                );
              }
            }

            completedCount++;
            bytesDownloaded += entry.sizeBytes;
            pendingEntriesToCommit.add(entry);
            if (payload != null) {
              downloadedGames.add(payload);
              pendingGamesToCommit.add(payload);
            }

            // Calculate smoothed ETA
            final elapsedSecs = downloadStopwatch.elapsedMilliseconds / 1000.0;
            if (completedCount >= 3 && elapsedSecs >= 1.5) {
              final rate = completedCount / elapsedSecs;
              final remaining = totalItems - completedCount;
              if (rate > 0.01) {
                final rawEta = remaining / rate;
                if (smoothedEtaSeconds < 0) {
                  smoothedEtaSeconds = rawEta;
                } else {
                  smoothedEtaSeconds = (smoothedEtaSeconds * 0.85) + (rawEta * 0.15);
                }
              }
            }

            String? etaText;
            if (completedCount < 3 || elapsedSecs < 1.5) {
              etaText = 'Estimating ETA...';
            } else if (completedCount >= totalItems) {
              etaText = 'Finishing...';
            } else if (smoothedEtaSeconds > 0) {
              final secs = smoothedEtaSeconds.round();
              if (secs < 60) {
                etaText = 'ETA: ${secs}s';
              } else {
                final mins = secs ~/ 60;
                final rem = secs % 60;
                etaText = rem > 0 ? 'ETA: ${mins}m ${rem}s' : 'ETA: ${mins}m';
              }
            }

            onProgress?.call(SyncProgress(
              phase: SyncPhase.downloadingPayloads,
              current: completedCount,
              total: totalItems,
              bytesDownloaded: bytesDownloaded,
              totalBytes: diff.totalDownloadBytes,
              message: 'Downloading $completedCount/$totalItems items ($itemName)...',
              currentItem: itemName,
              etaText: etaText,
              stepText: 'Step 2/3: Downloading Payloads & Offline Media',
            ));

            // Checkpoint commit: save batch of games to SQLite so interrupted/resumed sync works seamlessly!
            if (pendingEntriesToCommit.length >= commitBatchSize) {
              final batchGames = List<UnifiedGamePayload>.from(pendingGamesToCommit);
              final batchEntries = List<IndexEntry>.from(pendingEntriesToCommit);
              pendingGamesToCommit.clear();
              pendingEntriesToCommit.clear();

              await database.db.transaction((txn) async {
                if (batchGames.isNotEmpty) {
                  await gameDao.batchUpsertGames(batchGames, txn: txn);
                }
                if (batchEntries.isNotEmpty) {
                  await syncMetaDao.batchUpsertEntries(batchEntries, txn: txn);
                }
              });
            }
          } catch (e) {
            if (_isCancelled) break;
            rethrow;
          }
        }
      }

      final workers = List.generate(poolConcurrency, (_) => worker());
      await Future.wait(workers);

      // Handle user cancellation
      if (_isCancelled) {
        if (pendingGamesToCommit.isNotEmpty || pendingEntriesToCommit.isNotEmpty) {
          final batchGames = List<UnifiedGamePayload>.from(pendingGamesToCommit);
          final batchEntries = List<IndexEntry>.from(pendingEntriesToCommit);
          pendingGamesToCommit.clear();
          pendingEntriesToCommit.clear();

          await database.db.transaction((txn) async {
            if (batchGames.isNotEmpty) {
              await gameDao.batchUpsertGames(batchGames, txn: txn);
            }
            if (batchEntries.isNotEmpty) {
              await syncMetaDao.batchUpsertEntries(batchEntries, txn: txn);
            }
          });
        }
        await _backfillMediaDriveFileIds(remoteIndex);
        stopwatch.stop();

        onProgress?.call(SyncProgress(
          phase: SyncPhase.idle,
          current: completedCount,
          total: totalItems,
          bytesDownloaded: bytesDownloaded,
          totalBytes: diff.totalDownloadBytes,
          message: 'Sync cancelled by user. $completedCount items saved.',
          stepText: 'Sync Cancelled',
        ));

        return SyncReport.cancelled(
          downloadedCount: completedCount,
          bytesTransferred: bytesDownloaded,
          durationMs: stopwatch.elapsedMilliseconds,
        );
      }

      // Final checkpoint commit for any remaining items in queue
      if (pendingGamesToCommit.isNotEmpty || pendingEntriesToCommit.isNotEmpty) {
        final batchGames = List<UnifiedGamePayload>.from(pendingGamesToCommit);
        final batchEntries = List<IndexEntry>.from(pendingEntriesToCommit);
        pendingGamesToCommit.clear();
        pendingEntriesToCommit.clear();

        await database.db.transaction((txn) async {
          if (batchGames.isNotEmpty) {
            await gameDao.batchUpsertGames(batchGames, txn: txn);
          }
          if (batchEntries.isNotEmpty) {
            await syncMetaDao.batchUpsertEntries(batchEntries, txn: txn);
          }
        });
      }

      // 4. Finalize database state (orphan deletions and manifest)
      onProgress?.call(SyncProgress(
        phase: SyncPhase.committingDatabase,
        current: downloadedGames.length,
        total: diff.toDownload.length,
        bytesDownloaded: bytesDownloaded,
        totalBytes: diff.totalDownloadBytes,
        message: 'Finalizing database transaction...',
        currentItem: 'SQLite Database',
        stepText: 'Step 3/3: Saving to Local Database',
      ));

      await database.db.transaction((txn) async {
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
      });

      // Backfill missing media drive file IDs for all library games using remoteIndex
      await _backfillMediaDriveFileIds(remoteIndex);

      stopwatch.stop();
      onProgress?.call(SyncProgress(
        phase: SyncPhase.completed,
        current: completedCount,
        total: diff.toDownload.length,
        bytesDownloaded: bytesDownloaded,
        totalBytes: diff.totalDownloadBytes,
        message: 'Delta sync successfully completed in ${stopwatch.elapsedMilliseconds} ms.',
        stepText: 'Step 3/3: Complete',
      ));

      return SyncReport(
        isSuccess: true,
        downloadedCount: downloadedGames.isNotEmpty ? downloadedGames.length : completedCount,
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
    } finally {
      await BackgroundSyncService.releaseWakeLock();
    }
  }

  /// Backfills Google Drive file IDs for media (covers, backgrounds, icons, logos, trailers)
  /// on existing library games in SQLite using the remote SyncIndex.
  Future<void> _backfillMediaDriveFileIds(SyncIndex remoteIndex) async {
    try {
      final shaMap = <String, IndexEntry>{};
      for (final entry in remoteIndex.entries.values) {
        if (entry.sha256.isNotEmpty && entry.driveFileId.isNotEmpty) {
          shaMap[entry.sha256] = entry;
        }
      }

      final rows = await database.db.query(
        'games',
        columns: [
          'id',
          'cover_sha256',
          'background_sha256',
          'icon_sha256',
          'cover_drive_file_id',
          'background_drive_file_id',
          'icon_drive_file_id',
        ],
        where: 'cover_drive_file_id IS NULL OR background_drive_file_id IS NULL OR icon_drive_file_id IS NULL',
      );

      if (rows.isEmpty) return;

      final batch = database.db.batch();
      for (final row in rows) {
        final id = row['id'] as String;
        final coverSha = row['cover_sha256'] as String?;
        final bgSha = row['background_sha256'] as String?;
        final iconSha = row['icon_sha256'] as String?;

        final updates = <String, dynamic>{};
        if (coverSha != null && shaMap.containsKey(coverSha)) {
          updates['cover_drive_file_id'] = shaMap[coverSha]!.driveFileId;
        }
        if (bgSha != null && shaMap.containsKey(bgSha)) {
          updates['background_drive_file_id'] = shaMap[bgSha]!.driveFileId;
        }
        if (iconSha != null && shaMap.containsKey(iconSha)) {
          updates['icon_drive_file_id'] = shaMap[iconSha]!.driveFileId;
        }
        final logoEntry = remoteIndex.entries['media/logos/$id.png'];
        if (logoEntry != null && logoEntry.driveFileId.isNotEmpty) {
          updates['logo_drive_file_id'] = logoEntry.driveFileId;
        }
        final microEntry = remoteIndex.entries['media/microtrailers/$id.mp4'];
        if (microEntry != null && microEntry.driveFileId.isNotEmpty) {
          updates['microtrailer_drive_file_id'] = microEntry.driveFileId;
        }
        final trailerEntry = remoteIndex.entries['media/trailers/$id.mp4'];
        if (trailerEntry != null && trailerEntry.driveFileId.isNotEmpty) {
          updates['trailer_drive_file_id'] = trailerEntry.driveFileId;
        }

        if (updates.isNotEmpty) {
          batch.update('games', updates, where: 'id = ?', whereArgs: [id]);
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Media backfill warning: $e');
    }
  }

  /// Automatically aggregates and records total byte sizes for offline media tiers into manifest_meta.
  Future<void> _recordMediaTierSizes(SyncIndex remoteIndex) async {
    try {
      int coversAndFanartsBytes = 0;
      int completeOfflineBytes = 0;

      for (final entry in remoteIndex.entries.values) {
        final cat = AppConstants.normalizeCategory(entry.category);
        final path = entry.relativePath.toLowerCase();
        final isVideo = AppConstants.isVideoCategory(cat) ||
            entry.mimeType.startsWith('video/') ||
            path.endsWith('.mp4') ||
            path.endsWith('.webm') ||
            path.endsWith('.mkv');
        final isMedia = AppConstants.isMediaCategory(cat) ||
            isVideo ||
            path.startsWith('media/');

        if (isMedia) {
          completeOfflineBytes += entry.sizeBytes;
          if (!isVideo) {
            coversAndFanartsBytes += entry.sizeBytes;
          }
        }
      }

      await database.db.insert(
        'manifest_meta',
        {
          'key': 'media_tier_sizes',
          'value_json': jsonEncode({
            'covers_and_fanarts_bytes': coversAndFanartsBytes,
            'complete_offline_bytes': completeOfflineBytes,
          }),
          'updated_utc': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Media tier sizes record warning: $e');
    }
  }
}

