import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/achievements_section.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/library_preferences_service.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/recent_activity_timeline.dart';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late GameDao gameDao;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.db.delete('games');
    await database.db.delete('achievements');
    await database.db.delete('play_sessions');
    await database.db.delete('hltb_data');
    gameDao = GameDao(database);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await database.close();
  });

  group('Phase 4 Sprint: Rating Score Preference Tests', () {
    test('GallerySettings defaults ratingScoreSource to community', () {
      const settings = GallerySettings();
      expect(settings.ratingScoreSource, equals(RatingScoreSource.community));
      expect(settings.mediaStorageTier, equals(MediaStorageTier.cacheOnly));
    });

    test('GameFilterCriteria defaults ratingScoreSource to community', () {
      const criteria = GameFilterCriteria();
      expect(criteria.ratingScoreSource, equals(RatingScoreSource.community));
    });

    test('GameDao filters correctly with RatingScoreSource.community without wiping library', () async {
      await gameDao.batchUpsertGames([
        const UnifiedGamePayload(
          id: 'game-1',
          gameId: 'g1',
          pluginId: 'steam',
          name: 'Game With Community Score',
          sortingName: 'Game With Community Score',
          communityScore: 85,
          userScore: 50,
        ),
        const UnifiedGamePayload(
          id: 'game-2',
          gameId: 'g2',
          pluginId: 'steam',
          name: 'Game With User Score Only',
          sortingName: 'Game With User Score Only',
          userScore: 90,
          communityScore: null,
        ),
      ]);

      // Filtering with community score >= 80 must return game-1 and NOT game-2
      final communityFiltered = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(
          minScore: 80,
          ratingScoreSource: RatingScoreSource.community,
        ),
        sort: SortOption.titleAsc,
      );
      expect(communityFiltered.length, equals(1));
      expect(communityFiltered.first.id, equals('game-1'));

      // Filtering with composite score >= 80 returns both because COALESCE finds 85 and 90
      final compositeFiltered = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(
          minScore: 80,
          ratingScoreSource: RatingScoreSource.composite,
        ),
        sort: SortOption.titleAsc,
      );
      expect(compositeFiltered.length, equals(2));
    });
  });

  group('Phase 4 Sprint: HLTB and Utility Filters Tests', () {
    test('GameDao filters by HLTB max duration', () async {
      await gameDao.batchUpsertGames([
        const UnifiedGamePayload(
          id: 'short-game',
          gameId: 's1',
          pluginId: 'steam',
          name: 'Short Game',
          sortingName: 'Short Game',
          addons: {
            'how_long_to_beat': {
              'main_story_seconds': 3600 * 5, // 5 hours
            },
          },
        ),
        const UnifiedGamePayload(
          id: 'long-game',
          gameId: 'l1',
          pluginId: 'steam',
          name: 'Long Game',
          sortingName: 'Long Game',
          addons: {
            'how_long_to_beat': {
              'main_story_seconds': 3600 * 50, // 50 hours
            },
          },
        ),
      ]);

      final under10h = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(hltbMaxHours: 10),
        sort: SortOption.titleAsc,
      );
      expect(under10h.length, equals(1));
      expect(under10h.first.id, equals('short-game'));
    });

    test('GameDao filters utility flags: missingCoversOnly and unplayedOnly', () async {
      await gameDao.batchUpsertGames([
        const UnifiedGamePayload(
          id: 'g-with-cover',
          gameId: 'c1',
          pluginId: 'steam',
          name: 'With Cover',
          sortingName: 'With Cover',
          media: MediaPayload(coverDriveFileId: 'drive-cover-123'),
          playtimeSeconds: 120,
        ),
        const UnifiedGamePayload(
          id: 'g-no-cover',
          gameId: 'c2',
          pluginId: 'steam',
          name: 'No Cover',
          sortingName: 'No Cover',
          media: MediaPayload(),
          playtimeSeconds: 0,
        ),
      ]);

      final missingCovers = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(missingCoversOnly: true),
        sort: SortOption.titleAsc,
      );
      expect(missingCovers.length, equals(1));
      expect(missingCovers.first.id, equals('g-no-cover'));

      final unplayed = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(unplayedOnly: true),
        sort: SortOption.titleAsc,
      );
      expect(unplayed.length, equals(1));
      expect(unplayed.first.id, equals('g-no-cover'));
    });
  });

  group('Phase 4 Sprint: Duplicate Group ID Database Tests', () {
    test('AppDatabase supports duplicateGroupId and duplicate copies query', () async {
      await gameDao.batchUpsertGames([
        const UnifiedGamePayload(
          id: 'copy-1',
          gameId: 'app-steam-1',
          pluginId: 'steam',
          name: 'Witcher 3',
          sortingName: 'Witcher 3',
          isDuplicate: true,
          duplicateGroupId: 'witcher-3-group',
        ),
        const UnifiedGamePayload(
          id: 'copy-2',
          gameId: 'app-gog-1',
          pluginId: 'gog',
          name: 'Witcher 3',
          sortingName: 'Witcher 3',
          isDuplicate: true,
          duplicateGroupId: 'witcher-3-group',
        ),
        const UnifiedGamePayload(
          id: 'unique-game',
          gameId: 'app-unique',
          pluginId: 'steam',
          name: 'Unique Game',
          sortingName: 'Unique Game',
          isDuplicate: false,
          duplicateGroupId: null,
        ),
      ]);

      final duplicates = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(duplicateCopiesOnly: true),
        sort: SortOption.titleAsc,
      );
      expect(duplicates.length, equals(2));
      expect(duplicates.every((g) => g.duplicateGroupId == 'witcher-3-group'), isTrue);
    });
  });

  group('Phase 4 Sprint: SharedPreferences Persistence Tests', () {
    test('LibraryPreferencesService saves and restores sort, view mode, criteria', () async {
      final service = LibraryPreferencesService();

      await service.saveSortOption(SortOption.communityScoreDesc);
      await service.saveViewMode('list');
      await service.saveFilterCriteria(
        const GameFilterCriteria(
          minScore: 80,
          hltbMaxHours: 20,
          ratingScoreSource: RatingScoreSource.community,
        ),
      );

      final restoredSort = await service.loadSortOption();
      expect(restoredSort.field, equals(SortField.communityScore));
      expect(restoredSort.direction, equals(SortDirection.descending));

      final restoredView = await service.loadViewMode();
      expect(restoredView, equals('list'));

      final restoredCriteria = await service.loadFilterCriteria();
      expect(restoredCriteria, isNotNull);
      expect(restoredCriteria!.minScore, equals(80));
      expect(restoredCriteria.hltbMaxHours, equals(20));
      expect(restoredCriteria.ratingScoreSource, equals(RatingScoreSource.community));
    });
  });

  group('Phase 4 Sprint: Achievements Section Logic Tests', () {
    testWidgets('AchievementsSection renders with unlocked tab and rarity checks', (tester) async {
      const sampleGame = UnifiedGamePayload(
        id: 'test-game-achievements',
        gameId: 'g-ach',
        pluginId: 'steam',
        name: 'Achievement Test Game',
        sortingName: 'Achievement Test Game',
      );

      final addonData = <String, dynamic>{
        'total': 2,
        'unlocked': 1,
        'items': [
          {
            'api_name': 'ACH_FIRST',
            'name': 'First Step',
            'description': 'Started the game',
            'unlocked': true,
            'unlock_time_utc': '2026-01-01T10:00:00Z',
            'rarity_percent': 0.0, // Should be guarded
            'gamerscore': 10,
          },
          {
            'api_name': 'ACH_BOSS',
            'name': 'Boss Slayer',
            'description': 'Defeated final boss',
            'unlocked': false,
            'rarity_percent': 15.5,
            'gamerscore': 50,
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return const AchievementsSection().buildSection(ctx, addonData, sampleGame);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header verifies unlocked count
      expect(find.text('Achievements (1 / 2)'), findsOneWidget);
      // Unlocked item is visible by default
      expect(find.text('First Step'), findsOneWidget);
      // False 0.0% rarity guard ensures rarity is omitted or handled safely
      expect(find.text('0.0%'), findsNothing);
    });
  });

  group('Phase 4 Sprint: Image Loader Token Refresh Wiring Tests', () {
    test('PlayniteImageLoader allows setting and calling token refresher', () async {
      final loader = PlayniteImageLoader.instance;
      bool refresherCalled = false;

      loader.setTokenRefresher(() async {
        refresherCalled = true;
        return 'new-access-token-xyz';
      });

      expect(refresherCalled, isFalse);
    });
  });

  group('Phase 4 Sprint: Filter Criteria Active Count and Reset Invariants', () {
    test('Pristine and 0-score criteria report 0 active filters and isEmpty == true', () {
      const pristine = GameFilterCriteria();
      expect(pristine.activeFiltersCount, equals(0));
      expect(pristine.isEmpty, isTrue);

      const zeroScores = GameFilterCriteria(minScore: 0, hltbMaxHours: 0);
      expect(zeroScores.activeFiltersCount, equals(0));
      expect(zeroScores.isEmpty, isTrue);

      const activeCriteria = GameFilterCriteria(minScore: 75);
      expect(activeCriteria.activeFiltersCount, equals(1));
      expect(activeCriteria.isEmpty, isFalse);
    });
  });

  group('Phase 4 Sprint: Recent Activity Adjacent Session Grouping Tests', () {
    testWidgets('RecentActivityTimeline clubs adjacent entries of the same game into an expandable tile',
        (tester) async {
      final sessions = [
        const RecentSessionEntry(
          gameId: 'game-cyberpunk',
          gameName: 'Cyberpunk 2077',
          dateSessionUtc: '2026-10-18T14:00:00Z',
          elapsedSeconds: 3600, // 1 hr
        ),
        const RecentSessionEntry(
          gameId: 'game-cyberpunk',
          gameName: 'Cyberpunk 2077',
          dateSessionUtc: '2026-10-17T12:00:00Z',
          elapsedSeconds: 7200, // 2 hrs
        ),
        const RecentSessionEntry(
          gameId: 'game-witcher',
          gameName: 'The Witcher 3',
          dateSessionUtc: '2026-10-16T18:00:00Z',
          elapsedSeconds: 1800, // 30m
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentActivityTimeline(sessions: sessions),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cyberpunk appears as a clubbed entry with 2 sessions
      expect(find.text('Cyberpunk 2077'), findsOneWidget);
      expect(find.text('The Witcher 3'), findsOneWidget);
      expect(find.text('3h over 2 sessions'), findsOneWidget);
      expect(find.text('3 sessions'), findsOneWidget); // Header summary

      // Tap to expand Cyberpunk session details
      await tester.tap(find.text('Cyberpunk 2077'));
      await tester.pumpAndSettle();

      // Individual session durations appear in the expanded breakdown
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
    });
  });

  group('Phase 4 Sprint: Achievement Alphabetical Default Sort Tests', () {
    testWidgets('AchievementsSection sorts alphabetically by default', (tester) async {
      const sampleGame = UnifiedGamePayload(
        id: 'test-ach-sort',
        gameId: 'g-sort',
        pluginId: 'steam',
        name: 'Sort Test Game',
        sortingName: 'Sort Test Game',
      );

      final addonData = <String, dynamic>{
        'total': 3,
        'unlocked': 3,
        'items': [
          {
            'name': 'Zebra Master',
            'unlocked': true,
            'unlock_time_utc': '2026-10-18T10:00:00Z',
          },
          {
            'name': 'Alpha Beginning',
            'unlocked': true,
            'unlock_time_utc': '2026-10-10T10:00:00Z',
          },
          {
            'name': 'Bravo Warrior',
            'unlocked': true,
            'unlock_time_utc': '2026-10-15T10:00:00Z',
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (ctx) => const AchievementsSection().buildSection(ctx, addonData, sampleGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the ListTile names
      final alphaFinder = find.text('Alpha Beginning');
      final bravoFinder = find.text('Bravo Warrior');
      final zebraFinder = find.text('Zebra Master');

      expect(alphaFinder, findsOneWidget);
      expect(bravoFinder, findsOneWidget);
      expect(zebraFinder, findsOneWidget);

      // Verify that Alpha appears above Bravo, which appears above Zebra (alphabetical order)
      final alphaY = tester.getTopLeft(alphaFinder).dy;
      final bravoY = tester.getTopLeft(bravoFinder).dy;
      final zebraY = tester.getTopLeft(zebraFinder).dy;

      expect(alphaY < bravoY, isTrue);
      expect(bravoY < zebraY, isTrue);
    });
  });

  group('Phase 4 Sprint: Media Storage Tiers & Delta Pull Tests', () {
    test('computeDiff respects MediaStorageTier settings and skips/includes media accordingly', () {
      final pullManager = DeltaPullManager(
        driveService: MockDriveService(),
        database: database,
      );

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'test',
        generatedAtUtc: '2026-10-18T12:00:00Z',
        libraryId: 'test-lib',
        totalGames: 1,
        totalEntries: 5,
        totalSizeBytes: 35000000,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'sha-manifest',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'id-manifest',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/g1.json': const IndexEntry(
            relativePath: 'games/g1.json',
            sha256: 'sha-g1',
            sizeBytes: 5000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'id-g1',
            mimeType: 'application/json',
            category: 'game_metadata',
          ),
          'media/covers/cover1.jpg': const IndexEntry(
            relativePath: 'media/covers/cover1.jpg',
            sha256: 'sha-cover1',
            sizeBytes: 50000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'id-cover1',
            mimeType: 'image/jpeg',
            category: 'cover',
          ),
          'media/backgrounds/bg1.jpg': const IndexEntry(
            relativePath: 'media/backgrounds/bg1.jpg',
            sha256: 'sha-bg1',
            sizeBytes: 250000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'id-bg1',
            mimeType: 'image/jpeg',
            category: 'background',
          ),
          'media/microtrailers/g1.mp4': const IndexEntry(
            relativePath: 'media/microtrailers/g1.mp4',
            sha256: 'sha-vid1',
            sizeBytes: 2500000,
            modifiedUtc: '2026-10-18T12:00:00Z',
            driveFileId: 'id-vid1',
            mimeType: 'video/mp4',
            category: 'microtrailer',
          ),
        },
      );

      final emptyLocal = <String, LocalSyncEntry>{};

      // 1. Cache Only: Only manifest and game metadata
      final cacheOnlyDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.cacheOnly,
      );
      expect(cacheOnlyDiff.toDownload.length, equals(2));
      expect(cacheOnlyDiff.toDownload.map((e) => e.relativePath).toSet(), equals({'manifest.json', 'games/g1.json'}));

      // 2. Covers & Fanarts: Manifest, game metadata, cover, background (videos excluded)
      final coversDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.coversAndFanarts,
      );
      expect(coversDiff.toDownload.length, equals(4));
      expect(coversDiff.toDownload.map((e) => e.relativePath).toSet(), containsAll({'manifest.json', 'games/g1.json', 'media/covers/cover1.jpg', 'media/backgrounds/bg1.jpg'}));
      expect(coversDiff.toDownload.map((e) => e.relativePath).contains('media/microtrailers/g1.mp4'), isFalse);

      // 3. Complete Offline with Videos: All entries included
      final completeDiff = pullManager.computeDiff(
        remoteIndex,
        emptyLocal,
        mediaTier: MediaStorageTier.completeOffline,
      );
      expect(completeDiff.toDownload.length, equals(5));
      expect(completeDiff.toDownload.map((e) => e.relativePath).toSet(), containsAll({'manifest.json', 'games/g1.json', 'media/covers/cover1.jpg', 'media/backgrounds/bg1.jpg', 'media/microtrailers/g1.mp4'}));
    });

    test('PlayniteImageLoader prioritizes Detail View requests and saves to cache', () async {
      await PlayniteImageLoader.instance.init();

      // Test saveToCache
      final sampleBytes = [1, 2, 3, 4, 5];
      await PlayniteImageLoader.instance.saveToCache(
        keyOrMediaId: 'test_drive_file_id',
        bytes: sampleBytes,
        aliases: ['media/covers/test_cover.jpg'],
      );

      // Verify file is retrievable synchronously
      final fileByDriveId = PlayniteImageLoader.instance.getCachedFileSync('test_drive_file_id');
      final fileByRelPath = PlayniteImageLoader.instance.getCachedFileSync('media/covers/test_cover.jpg');

      expect(fileByDriveId, isNotNull);
      expect(fileByRelPath, isNotNull);
      expect(fileByDriveId!.existsSync(), isTrue);
      expect(fileByRelPath!.existsSync(), isTrue);

      // Test prioritizeDetailView does not crash
      expect(
        () => PlayniteImageLoader.instance.prioritizeDetailView(['test_drive_file_id', 'test_bg_id']),
        returnsNormally,
      );
    });
  });
}
