import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_constants.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Media Category Parity & Normalization (Issue #2)', () {
    test('AppConstants media category constants match desktop sync index enum keys', () {
      expect(AppConstants.categoryCover, equals('cover'));
      expect(AppConstants.categoryBackground, equals('background'));
      expect(AppConstants.categoryLogo, equals('logo'));
      expect(AppConstants.categoryMicrotrailer, equals('microtrailer'));
      expect(AppConstants.categoryTrailer, equals('trailer'));
      expect(AppConstants.categoryManifest, equals('manifest'));
      expect(AppConstants.categoryGameMetadata, equals('game_metadata'));
    });

    test('AppConstants legacy constants are maintained for backwards compatibility', () {
      expect(AppConstants.legacyCategoryCover, equals('media_cover'));
      expect(AppConstants.legacyCategoryBackground, equals('media_background'));
      expect(AppConstants.legacyCategoryLogo, equals('media_logo'));
      expect(AppConstants.legacyCategoryMicrotrailer, equals('media_microtrailer'));
      expect(AppConstants.legacyCategoryTrailer, equals('media_trailer'));
    });

    test('AppConstants.normalizeCategory maps legacy media_ categories to canonical keys', () {
      expect(AppConstants.normalizeCategory('media_cover'), equals('cover'));
      expect(AppConstants.normalizeCategory('media_background'), equals('background'));
      expect(AppConstants.normalizeCategory('media_logo'), equals('logo'));
      expect(AppConstants.normalizeCategory('media_microtrailer'), equals('microtrailer'));
      expect(AppConstants.normalizeCategory('media_trailer'), equals('trailer'));

      // Canonical and case-insensitive
      expect(AppConstants.normalizeCategory('cover'), equals('cover'));
      expect(AppConstants.normalizeCategory('COVER'), equals('cover'));
      expect(AppConstants.normalizeCategory('Background'), equals('background'));
      expect(AppConstants.normalizeCategory('logo'), equals('logo'));
      expect(AppConstants.normalizeCategory('microtrailer'), equals('microtrailer'));
      expect(AppConstants.normalizeCategory('trailer'), equals('trailer'));
      expect(AppConstants.normalizeCategory('manifest'), equals('manifest'));
      expect(AppConstants.normalizeCategory('game_metadata'), equals('game_metadata'));
      expect(AppConstants.normalizeCategory('icon'), equals('icon'));
      expect(AppConstants.normalizeCategory(null), equals(''));
    });

    test('IndexEntry and LocalSyncEntry normalize legacy category strings', () {
      final indexEntry = IndexEntry.fromJson('media/covers/abc.jpg', {
        'sha256': 'hash1',
        'size_bytes': 1234,
        'category': 'media_cover',
      });
      expect(indexEntry.category, equals(AppConstants.categoryCover));

      final localEntry = LocalSyncEntry.fromMap({
        'relative_path': 'media/microtrailers/g1.mp4',
        'sha256': 'hash2',
        'size_bytes': 5678,
        'modified_utc': '2026-10-18T12:00:00Z',
        'drive_file_id': 'd2',
        'mime_type': 'video/mp4',
        'category': 'media_microtrailer',
        'game_id': 'g1',
        'last_synced_utc': '2026-10-18T12:00:00Z',
      });
      expect(localEntry.category, equals(AppConstants.categoryMicrotrailer));
    });

    test('AppDatabase migrates legacy media_ categories in sync_entries table', () async {
      final database = AppDatabase.instance;
      await database.init(inMemory: true);
      await database.reset();

      // Insert legacy rows directly into sync_entries
      await database.db.insert('sync_entries', {
        'relative_path': 'media/covers/c1.jpg',
        'sha256': 'hash_c1',
        'size_bytes': 1000,
        'modified_utc': '2026-10-18T12:00:00Z',
        'drive_file_id': 'id_c1',
        'mime_type': 'image/jpeg',
        'category': 'media_cover',
        'game_id': 'g1',
        'last_synced_utc': '2026-10-18T12:00:00Z',
      });

      await database.db.insert('sync_entries', {
        'relative_path': 'media/microtrailers/g1.mp4',
        'sha256': 'hash_v1',
        'size_bytes': 2000000,
        'modified_utc': '2026-10-18T12:00:00Z',
        'drive_file_id': 'id_v1',
        'mime_type': 'video/mp4',
        'category': 'media_microtrailer',
        'game_id': 'g1',
        'last_synced_utc': '2026-10-18T12:00:00Z',
      });

      // Execute migration
      await database.migrateLegacyCategories();

      final rows = await database.db.query('sync_entries', orderBy: 'relative_path ASC');
      expect(rows.length, equals(2));
      expect(rows[0]['category'], equals('cover'));
      expect(rows[1]['category'], equals('microtrailer'));

      await database.close();
    });

    test('AppDatabase migrates legacy media_ categories in sync_entries table on file init', () async {
      final tempDir = Directory.systemTemp.createTempSync('playnite_test_db_');
      final dbPath = '${tempDir.path}/test_companion.db';

      try {
        final database = AppDatabase.instance;
        await database.init(customPath: dbPath);
        await database.reset();

        // Insert legacy rows directly into sync_entries
        await database.db.insert('sync_entries', {
          'relative_path': 'media/covers/c1.jpg',
          'sha256': 'hash_c1',
          'size_bytes': 1000,
          'modified_utc': '2026-10-18T12:00:00Z',
          'drive_file_id': 'id_c1',
          'mime_type': 'image/jpeg',
          'category': 'media_cover',
          'game_id': 'g1',
          'last_synced_utc': '2026-10-18T12:00:00Z',
        });

        await database.db.insert('sync_entries', {
          'relative_path': 'media/backgrounds/bg1.jpg',
          'sha256': 'hash_bg1',
          'size_bytes': 2000,
          'modified_utc': '2026-10-18T12:00:00Z',
          'drive_file_id': 'id_bg1',
          'mime_type': 'image/jpeg',
          'category': 'media_background',
          'game_id': 'g1',
          'last_synced_utc': '2026-10-18T12:00:00Z',
        });

        // Close connection and re-open to trigger automatic _migrateLegacyCategories in init()
        await database.close();
        await database.init(customPath: dbPath);

        final rows = await database.db.query('sync_entries', orderBy: 'relative_path ASC');
        expect(rows.length, equals(2));
        expect(rows[0]['category'], equals('background'));
        expect(rows[1]['category'], equals('cover'));

        await database.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('DeltaPullManager.computeDiff handles both canonical and legacy categories in remote and local', () {
      final pullManager = DeltaPullManager(
        driveService: MockDriveService(),
        database: AppDatabase.instance,
      );

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-18T12:00:00Z',
        libraryId: 'lib-1',
        totalGames: 1,
        totalEntries: 5,
        totalSizeBytes: 3000000,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h-manifest',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'd-manifest',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/g1.json': const IndexEntry(
            relativePath: 'games/g1.json',
            sha256: 'h-g1',
            sizeBytes: 5000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'd-g1',
            mimeType: 'application/json',
            category: 'game_metadata',
          ),
          'media/covers/cover1.jpg': const IndexEntry(
            relativePath: 'media/covers/cover1.jpg',
            sha256: 'h-cover',
            sizeBytes: 50000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'd-cover',
            mimeType: 'image/jpeg',
            category: 'cover',
          ),
          'media/logos/logo1.png': const IndexEntry(
            relativePath: 'media/logos/logo1.png',
            sha256: 'h-logo',
            sizeBytes: 30000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'd-logo',
            mimeType: 'image/png',
            category: 'logo',
          ),
          'media/microtrailers/g1.mp4': const IndexEntry(
            relativePath: 'media/microtrailers/g1.mp4',
            sha256: 'h-micro',
            sizeBytes: 2000000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'd-micro',
            mimeType: 'video/mp4',
            category: 'microtrailer',
          ),
        },
      );

      final emptyLocal = <String, LocalSyncEntry>{};

      // 1. cacheOnly: only manifest & game_metadata
      final cacheOnlyDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.cacheOnly,
      );
      expect(cacheOnlyDiff.toDownload.map((e) => e.relativePath).toSet(), equals({'manifest.json', 'games/g1.json'}));

      // 2. coversAndFanarts: includes covers and logos, excludes microtrailers
      final coversDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.coversAndFanarts,
      );
      expect(
        coversDiff.toDownload.map((e) => e.relativePath).toSet(),
        equals({'manifest.json', 'games/g1.json', 'media/covers/cover1.jpg', 'media/logos/logo1.png'}),
      );

      // 3. completeOffline: includes all assets including microtrailers
      final offlineDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.completeOffline,
      );
      expect(offlineDiff.toDownload.length, equals(5));
    });
  });
}
