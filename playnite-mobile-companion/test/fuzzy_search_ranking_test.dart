import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/utils/fuzzy_search_engine.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('FuzzySearchEngine Unit Tests', () {
    test('1. Levenshtein distance calculations are accurate', () {
      expect(FuzzySearchEngine.levenshtein('kitten', 'sitting'), equals(3));
      expect(FuzzySearchEngine.levenshtein('Eternm', 'Eternum'), equals(1));
      expect(FuzzySearchEngine.levenshtein('Silksongg', 'Silksong'), equals(1));
      expect(FuzzySearchEngine.levenshtein('same', 'same'), equals(0));
      expect(FuzzySearchEngine.levenshtein('', 'test'), equals(4));
    });

    test('2. Exact and prefix title matches rank in Tier 1', () {
      const gameExact = UnifiedGamePayload(
        id: '1',
        gameId: '1',
        pluginId: 'steam',
        name: 'Portal',
        sortingName: 'Portal',
      );
      const gamePrefix = UnifiedGamePayload(
        id: '2',
        gameId: '2',
        pluginId: 'steam',
        name: 'Portal 2',
        sortingName: 'Portal 2',
      );
      const gameWordPrefix = UnifiedGamePayload(
        id: '3',
        gameId: '3',
        pluginId: 'steam',
        name: 'Bridge Constructor Portal',
        sortingName: 'Bridge Constructor Portal',
      );
      const gameSubstring = UnifiedGamePayload(
        id: '4',
        gameId: '4',
        pluginId: 'steam',
        name: 'Teleportation',
        sortingName: 'Teleportation',
      );

      final rExact = FuzzySearchEngine.rankGame(gameExact, 'Portal');
      final rPrefix = FuzzySearchEngine.rankGame(gamePrefix, 'Portal');
      final rWord = FuzzySearchEngine.rankGame(gameWordPrefix, 'Portal');
      final rSub = FuzzySearchEngine.rankGame(gameSubstring, 'port');

      expect(rExact, isNotNull);
      expect(rPrefix, isNotNull);
      expect(rWord, isNotNull);
      expect(rSub, isNotNull);

      expect(rExact!.tier, equals(SearchTier.tier1Exact));
      expect(rPrefix!.tier, equals(SearchTier.tier1Prefix));
      expect(rWord!.tier, equals(SearchTier.tier1WordPrefix));
      expect(rSub!.tier, equals(SearchTier.tier1Substring));

      // Ordering: exact < prefix < word prefix
      expect(rExact.score, lessThan(rPrefix.score));
      expect(rPrefix.score, lessThan(rWord.score));
    });

    test('3. Typo-tolerant title matches rank in Tier 2', () {
      const gameEternum = UnifiedGamePayload(
        id: '1',
        gameId: '1',
        pluginId: 'itch',
        name: 'Eternum',
        sortingName: 'Eternum',
      );
      const gameSilksong = UnifiedGamePayload(
        id: '2',
        gameId: '2',
        pluginId: 'steam',
        name: 'Hollow Knight: Silksong',
        sortingName: 'Hollow Knight: Silksong',
      );

      final rEternum = FuzzySearchEngine.rankGame(gameEternum, 'Eternm');
      final rSilksong = FuzzySearchEngine.rankGame(gameSilksong, 'Silksongg');

      expect(rEternum, isNotNull);
      expect(rEternum!.tier, equals(SearchTier.tier2Fuzzy));

      expect(rSilksong, isNotNull);
      expect(rSilksong!.tier, equals(SearchTier.tier2Fuzzy));
    });

    test('4. Metadata matches (developer, genre, tag, description) rank in Tier 3', () {
      const gameDev = UnifiedGamePayload(
        id: '1',
        gameId: '1',
        pluginId: 'steam',
        name: 'Cyberpunk 2077',
        sortingName: 'Cyberpunk 2077',
        developers: [NamedItem(id: 'cdpr', name: 'CD Projekt RED')],
      );
      const gameGenre = UnifiedGamePayload(
        id: '2',
        gameId: '2',
        pluginId: 'steam',
        name: 'Dead Cells',
        sortingName: 'Dead Cells',
        genres: [NamedItem(id: 'rogue', name: 'Roguelike')],
      );
      const gameDesc = UnifiedGamePayload(
        id: '3',
        gameId: '3',
        pluginId: 'steam',
        name: 'Fallout 4',
        sortingName: 'Fallout 4',
        description: 'Explore a devastated post-apocalyptic Boston wasteland.',
      );

      final rDev = FuzzySearchEngine.rankGame(gameDev, 'CD Projekt');
      final rGenre = FuzzySearchEngine.rankGame(gameGenre, 'Roguelike');
      final rDesc = FuzzySearchEngine.rankGame(gameDesc, 'post-apocalyptic');

      expect(rDev, isNotNull);
      expect(rGenre, isNotNull);
      expect(rDesc, isNotNull);

      expect(rDev!.tier, equals(SearchTier.tier3Metadata));
      expect(rGenre!.tier, equals(SearchTier.tier3Metadata));
      expect(rDesc!.tier, equals(SearchTier.tier3Metadata));
    });

    test('5. Multi-tier ranking order: Tier 1 > Tier 2 > Tier 3', () {
      const g1Exact = UnifiedGamePayload(
        id: '1',
        gameId: '1',
        pluginId: 'p',
        name: 'Witcher',
        sortingName: 'Witcher',
      );
      const g2Fuzzy = UnifiedGamePayload(
        id: '2',
        gameId: '2',
        pluginId: 'p',
        name: 'Wicher Adventures',
        sortingName: 'Wicher Adventures',
      );
      const g3Meta = UnifiedGamePayload(
        id: '3',
        gameId: '3',
        pluginId: 'p',
        name: 'Gwent',
        sortingName: 'Gwent',
        description: 'A spin-off game set in the Witcher universe.',
      );
      const g4Unrelated = UnifiedGamePayload(
        id: '4',
        gameId: '4',
        pluginId: 'p',
        name: 'Super Mario',
        sortingName: 'Super Mario',
      );

      final ranked = FuzzySearchEngine.filterAndRank(
        [g3Meta, g4Unrelated, g1Exact, g2Fuzzy],
        'Witcher',
        baseSort: SortOption.titleAsc,
      );

      expect(ranked.length, equals(3));
      expect(ranked[0].id, equals('1')); // Tier 1
      expect(ranked[1].id, equals('2')); // Tier 2
      expect(ranked[2].id, equals('3')); // Tier 3
    });
  });

  group('GameDao Two-Tier Fuzzy Search Integration Tests', () {
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
          id: 'g-eternum',
          gameId: 'g-eternum',
          pluginId: 'itch',
          name: 'Eternum',
          sortingName: 'Eternum',
        ),
        const UnifiedGamePayload(
          id: 'g-silksong',
          gameId: 'g-silksong',
          pluginId: 'steam',
          name: 'Hollow Knight: Silksong',
          sortingName: 'Hollow Knight: Silksong',
        ),
        const UnifiedGamePayload(
          id: 'g-witcher3',
          gameId: 'g-witcher3',
          pluginId: 'steam',
          name: 'The Witcher 3: Wild Hunt',
          sortingName: 'Witcher 3: Wild Hunt',
          developers: [NamedItem(id: 'cdpr', name: 'CD Projekt RED')],
        ),
        const UnifiedGamePayload(
          id: 'g-cyberpunk',
          gameId: 'g-cyberpunk',
          pluginId: 'gog',
          name: 'Cyberpunk 2077',
          sortingName: 'Cyberpunk 2077',
          developers: [NamedItem(id: 'cdpr', name: 'CD Projekt RED')],
          description: 'Open world action adventure RPG.',
        ),
      ]);
    });

    tearDown(() async {
      await database.close();
    });

    test('6. Typing "Eternm" (typo) finds Eternum in GameDao', () async {
      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Eternm'),
        sort: SortOption.titleAsc,
      );

      expect(games.length, equals(1));
      expect(games.first.name, equals('Eternum'));
    });

    test('7. Typing "Silksongg" (typo) finds Hollow Knight: Silksong in GameDao', () async {
      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Silksongg'),
        sort: SortOption.titleAsc,
      );

      expect(games.length, equals(1));
      expect(games.first.name, equals('Hollow Knight: Silksong'));
    });

    test('8. Searching metadata "CD Projekt" finds both Witcher 3 and Cyberpunk 2077', () async {
      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'CD Projekt'),
        sort: SortOption.titleAsc,
      );

      final names = games.map((g) => g.name).toList();
      expect(names, contains('The Witcher 3: Wild Hunt'));
      expect(names, contains('Cyberpunk 2077'));
    });

    test('9. Search query with exact title match ranks above metadata match', () async {
      // "Cyberpunk" is exact/prefix of "Cyberpunk 2077" (Tier 1)
      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Cyberpunk'),
        sort: SortOption.titleAsc,
      );

      expect(games.isNotEmpty, isTrue);
      expect(games.first.name, equals('Cyberpunk 2077'));
    });
  });
}
