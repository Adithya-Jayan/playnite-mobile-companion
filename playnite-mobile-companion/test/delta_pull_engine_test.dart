import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late GameDao gameDao;
  late SyncMetaDao syncMetaDao;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);
    syncMetaDao = SyncMetaDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('Delta-Pull Engine Invariant Tests', () {
    test('given a 500-game mock library where only 2 games have different hashes, asserts exactly 2 network GET requests are dispatched for game JSONs', () async {
      final mockService = MockDriveService();

      // 1. Setup initial 500 games in local database and local sync metadata
      final initialGames = <UnifiedGamePayload>[];
      final initialSyncEntries = <IndexEntry>[];
      final remoteIndexEntries = <String, IndexEntry>{};

      for (var i = 1; i <= 500; i++) {
        final id = 'game-uuid-$i';
        final initialHash = 'hash-v1-$i';
        final path = 'games/$id.json';

        final game = UnifiedGamePayload(
          id: id,
          gameId: 'store-$i',
          pluginId: 'plugin-guid',
          name: 'Game #$i',
          sortingName: 'Game #$i',
          playtimeSeconds: i * 360,
        );
        initialGames.add(game);

        final entry = IndexEntry(
          relativePath: path,
          sha256: initialHash,
          sizeBytes: 12000,
          modifiedUtc: '2026-10-15T20:00:00.000Z',
          driveFileId: 'drive-id-$i',
          mimeType: 'application/json',
          category: 'game_metadata',
          gameId: id,
        );
        initialSyncEntries.add(entry);

        // Remote index entries initially match
        remoteIndexEntries[path] = entry;
      }

      // Ingest initial 500 games into SQLite
      await gameDao.batchUpsertGames(initialGames);
      await syncMetaDao.batchUpsertEntries(initialSyncEntries);

      expect(await gameDao.getGamesCount(), equals(500));

      // 2. Mutate exactly 2 games in the remote index (e.g. game #42 and #389)
      final mutatedId1 = 'game-uuid-42';
      final mutatedId2 = 'game-uuid-389';

      final updatedGame42 = UnifiedGamePayload(
        id: mutatedId1,
        gameId: 'store-42',
        pluginId: 'plugin-guid',
        name: 'Game #42 (Updated Edition)',
        sortingName: 'Game #42',
        playtimeSeconds: 72000, // playtime updated
      );
      final updatedGame389 = UnifiedGamePayload(
        id: mutatedId2,
        gameId: 'store-389',
        pluginId: 'plugin-guid',
        name: 'Game #389 (DLC Added)',
        sortingName: 'Game #389',
        playtimeSeconds: 84000,
      );

      final newEntry42 = IndexEntry(
        relativePath: 'games/$mutatedId1.json',
        sha256: 'NEW-DIFFERENT-HASH-FOR-42',
        sizeBytes: 12500,
        modifiedUtc: '2026-10-15T21:30:00.000Z',
        driveFileId: 'drive-id-42-v2',
        mimeType: 'application/json',
        category: 'game_metadata',
        gameId: mutatedId1,
      );
      final newEntry389 = IndexEntry(
        relativePath: 'games/$mutatedId2.json',
        sha256: 'NEW-DIFFERENT-HASH-FOR-389',
        sizeBytes: 12800,
        modifiedUtc: '2026-10-15T21:35:00.000Z',
        driveFileId: 'drive-id-389-v2',
        mimeType: 'application/json',
        category: 'game_metadata',
        gameId: mutatedId2,
      );

      remoteIndexEntries['games/$mutatedId1.json'] = newEntry42;
      remoteIndexEntries['games/$mutatedId2.json'] = newEntry389;

      // Provide updated JSON files on mock service
      mockService.setFile('drive-id-42-v2', jsonEncode(updatedGame42.toDatabaseRow()..addAll({'addons': {}})));
      mockService.setFile('drive-id-389-v2', jsonEncode(updatedGame389.toDatabaseRow()..addAll({'addons': {}})));

      // Set the remote index
      mockService.mockIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T21:40:00.000Z',
        libraryId: 'test-lib',
        totalGames: 500,
        totalEntries: 500,
        totalSizeBytes: 6000000,
        entries: remoteIndexEntries,
      );

      mockService.resetMetrics();

      // 3. Execute Delta Pull
      final pullManager = DeltaPullManager(
        driveService: mockService,
        database: database,
      );

      final report = await pullManager.executeDeltaPull();

      // 4. Assert strict incremental invariants
      expect(report.isSuccess, isTrue);
      expect(report.downloadedCount, equals(2));
      expect(report.deletedCount, equals(0));

      // CRITICAL INVARIANT: Exactly 2 game payload GET requests were dispatched across the network!
      expect(mockService.gamePayloadRequests, equals(2));
      // Total GET requests = 1 (fetchSyncIndex) + 2 (games) = 3
      expect(mockService.totalGetRequests, equals(3));
      expect(mockService.requestedPaths, containsAll(['drive-id-42-v2', 'drive-id-389-v2']));

      // 5. Verify local database was updated correctly
      final loaded42 = await gameDao.getGameById(mutatedId1);
      final loaded389 = await gameDao.getGameById(mutatedId2);
      expect(loaded42?.name, equals('Game #42 (Updated Edition)'));
      expect(loaded42?.playtimeSeconds, equals(72000));
      expect(loaded389?.name, equals('Game #389 (DLC Added)'));
      expect(loaded389?.playtimeSeconds, equals(84000));

      // 6. Second pull with 0 changes -> Strict No-Op
      mockService.resetMetrics();
      final noOpReport = await pullManager.executeDeltaPull();
      expect(noOpReport.isSuccess, isTrue);
      expect(noOpReport.downloadedCount, equals(0));
      expect(noOpReport.deletedCount, equals(0));
      expect(mockService.gamePayloadRequests, equals(0)); // 0 downloads!
    });

    test('Orphan Pruning: deletes removed games from local SQLite and sync_entries', () async {
      final mockService = MockDriveService();

      // Seed 3 games
      final g1 = UnifiedGamePayload(id: 'g1', gameId: 's1', pluginId: 'p', name: 'Game 1', sortingName: 'Game 1');
      final g2 = UnifiedGamePayload(id: 'g2', gameId: 's2', pluginId: 'p', name: 'Game 2', sortingName: 'Game 2');
      final g3 = UnifiedGamePayload(id: 'g3', gameId: 's3', pluginId: 'p', name: 'Game 3', sortingName: 'Game 3');

      await gameDao.batchUpsertGames([g1, g2, g3]);
      await syncMetaDao.batchUpsertEntries([
        IndexEntry(relativePath: 'games/g1.json', sha256: 'h1', sizeBytes: 100, modifiedUtc: '', driveFileId: 'd1', mimeType: 'json', category: 'game_metadata', gameId: 'g1'),
        IndexEntry(relativePath: 'games/g2.json', sha256: 'h2', sizeBytes: 100, modifiedUtc: '', driveFileId: 'd2', mimeType: 'json', category: 'game_metadata', gameId: 'g2'),
        IndexEntry(relativePath: 'games/g3.json', sha256: 'h3', sizeBytes: 100, modifiedUtc: '', driveFileId: 'd3', mimeType: 'json', category: 'game_metadata', gameId: 'g3'),
      ]);

      expect(await gameDao.getGamesCount(), equals(3));

      // Remote index now omits g2 (it was deleted on desktop)
      mockService.mockIndex = SyncIndex(
        version: '1.0.0',
        generator: 'plugin',
        generatedAtUtc: '',
        libraryId: 'lib',
        totalGames: 2,
        totalEntries: 2,
        totalSizeBytes: 200,
        entries: {
          'games/g1.json': IndexEntry(relativePath: 'games/g1.json', sha256: 'h1', sizeBytes: 100, modifiedUtc: '', driveFileId: 'd1', mimeType: 'json', category: 'game_metadata', gameId: 'g1'),
          'games/g3.json': IndexEntry(relativePath: 'games/g3.json', sha256: 'h3', sizeBytes: 100, modifiedUtc: '', driveFileId: 'd3', mimeType: 'json', category: 'game_metadata', gameId: 'g3'),
        },
      );

      final pullManager = DeltaPullManager(driveService: mockService, database: database);
      final report = await pullManager.executeDeltaPull();

      expect(report.isSuccess, isTrue);
      expect(report.deletedCount, equals(1));
      expect(report.downloadedCount, equals(0));

      expect(await gameDao.getGamesCount(), equals(2));
      expect(await gameDao.getGameById('g2'), isNull);
      expect(await gameDao.getGameById('g1'), isNotNull);
      expect(await gameDao.getGameById('g3'), isNotNull);

      // Verify sync_entries no longer has g2
      final localEntries = await syncMetaDao.getAllEntriesMap();
      expect(localEntries.containsKey('games/g2.json'), isFalse);
    });
  });
}
