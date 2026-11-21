import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
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
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);

    await gameDao.batchUpsertGames([
      const UnifiedGamePayload(
        id: 'game-normal',
        gameId: 'game-normal',
        pluginId: 'steam',
        name: 'The Witcher 3: Wild Hunt',
        sortingName: 'Witcher 3: Wild Hunt',
        hidden: false,
        isDuplicate: false,
        playtimeSeconds: 3600,
      ),
      const UnifiedGamePayload(
        id: 'game-eternum',
        gameId: 'game-eternum',
        pluginId: 'itch',
        name: 'Eternum',
        sortingName: 'Eternum',
        hidden: true,
        isDuplicate: false,
        playtimeSeconds: 7200,
      ),
      const UnifiedGamePayload(
        id: 'game-duplicate-hidden',
        gameId: 'game-duplicate-hidden',
        pluginId: 'gog',
        name: 'The Witcher 3 (GOG Duplicate)',
        sortingName: 'Witcher 3 GOG Duplicate',
        hidden: true,
        isDuplicate: true,
        playtimeSeconds: 0,
      ),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  group('Ticket #29: Baseline Visibility & Eternum Fix (DAO Tests)', () {
    test('1. Default visibility excludes user hidden games and DuplicateHider copies', () async {
      const criteria = GameFilterCriteria(
        includeUserHidden: false,
        includeDuplicateHider: false,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names, contains('The Witcher 3: Wild Hunt'));
      expect(names, isNot(contains('Eternum')));
      expect(names, isNot(contains('The Witcher 3 (GOG Duplicate)')));
    });

    test('2. includeUserHidden: true alone displays Eternum while suppressing duplicates', () async {
      const criteria = GameFilterCriteria(
        includeUserHidden: true,
        includeDuplicateHider: false,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names, contains('The Witcher 3: Wild Hunt'));
      expect(names, contains('Eternum'));
      expect(names, isNot(contains('The Witcher 3 (GOG Duplicate)')));
    });

    test('3. includeDuplicateHider: true alone displays duplicates while suppressing Eternum', () async {
      const criteria = GameFilterCriteria(
        includeUserHidden: false,
        includeDuplicateHider: true,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names, contains('The Witcher 3: Wild Hunt'));
      expect(names, contains('The Witcher 3 (GOG Duplicate)'));
      expect(names, isNot(contains('Eternum')));
    });

    test('4. Both includeUserHidden and includeDuplicateHider enabled displays ALL games unconditionally', () async {
      const criteria = GameFilterCriteria(
        includeUserHidden: true,
        includeDuplicateHider: true,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names.length, equals(3));
      expect(names, contains('The Witcher 3: Wild Hunt'));
      expect(names, contains('Eternum'));
      expect(names, contains('The Witcher 3 (GOG Duplicate)'));
    });
  });

  group('Ticket #29: GallerySettings Persistence & Triage Integration Tests', () {
    test('5. GallerySettings repository updates propagate to effective criteria and reveal Eternum', () async {
      final galleryRepo = GallerySettingsRepository(database);

      // 1. Initial default state: user-hidden games are excluded
      await galleryRepo.saveSettings(const GallerySettings(
        includeUserHiddenGames: false,
        includeDuplicateHiderGames: false,
      ));

      final settings1 = await galleryRepo.loadSettings();
      final criteria1 = const GameFilterCriteria().copyWith(
        includeUserHidden: settings1.includeUserHiddenGames,
        includeDuplicateHider: settings1.includeDuplicateHiderGames,
      );
      final games1 = await gameDao.getFilteredGames(criteria: criteria1, sort: SortOption.titleAsc);
      final names1 = games1.map((g) => g.name).toList();

      expect(names1, contains('The Witcher 3: Wild Hunt'));
      expect(names1, isNot(contains('Eternum')));
      expect(names1, isNot(contains('The Witcher 3 (GOG Duplicate)')));

      // 2. User enables both user-hidden games and duplicate hider copies
      await galleryRepo.saveSettings(const GallerySettings(
        includeUserHiddenGames: true,
        includeDuplicateHiderGames: true,
      ));

      final settings2 = await galleryRepo.loadSettings();
      final criteria2 = const GameFilterCriteria().copyWith(
        includeUserHidden: settings2.includeUserHiddenGames,
        includeDuplicateHider: settings2.includeDuplicateHiderGames,
      );
      final games2 = await gameDao.getFilteredGames(criteria: criteria2, sort: SortOption.titleAsc);
      final names2 = games2.map((g) => g.name).toList();

      expect(names2.length, equals(3));
      expect(names2, contains('The Witcher 3: Wild Hunt'));
      expect(names2, contains('Eternum'));
      expect(names2, contains('The Witcher 3 (GOG Duplicate)'));
    });

    test('6. UtilityFilterMode.onlyHidden reveals Eternum while separating duplicate copies', () async {
      const criteria = GameFilterCriteria(
        utilityMode: UtilityFilterMode.onlyHidden,
        includeUserHidden: false,
        includeDuplicateHider: false,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names, contains('Eternum'));
      expect(names, isNot(contains('The Witcher 3 (GOG Duplicate)')));
      expect(names, isNot(contains('The Witcher 3: Wild Hunt')));
    });

    test('7. UtilityFilterMode.onlyDuplicates reveals duplicate copies while separating user-hidden games', () async {
      const criteria = GameFilterCriteria(
        utilityMode: UtilityFilterMode.onlyDuplicates,
        includeUserHidden: false,
        includeDuplicateHider: false,
      );
      final games = await gameDao.getFilteredGames(criteria: criteria, sort: SortOption.titleAsc);
      final names = games.map((g) => g.name).toList();

      expect(names, contains('The Witcher 3 (GOG Duplicate)'));
      expect(names, isNot(contains('Eternum')));
      expect(names, isNot(contains('The Witcher 3: Wild Hunt')));
    });
  });
}
