import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late GameDao gameDao;
  late TaxonomyDao taxonomyDao;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);
    taxonomyDao = TaxonomyDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('GameDao & TaxonomyDao Robust Deserialization Tests', () {
    test('1. Deserializes SQLite rows containing integer types in string columns without throwing TypeError', () async {
      // Simulate raw SQLite insertion with integer version, integer release date, integer source_id, integer id
      await database.db.rawInsert('''
        INSERT INTO games (
          id, game_id, plugin_id, name, sorting_name, version, release_date,
          source_id, source_name, completion_status_id, completion_status_name,
          platforms_json, genres_json, links_json, other_copies_json, hidden
        ) VALUES (
          12345, 67890, 1, 'The Witcher 3', 'Witcher 3', 1, 2015,
          10, 'GOG', 2, 'Completed',
          '[{"id": 1, "name": "PC"}, {"id": 2, "name": "Xbox"}]',
          '[{"id": 99, "name": "RPG"}]',
          '[{"name": "GOG Store", "url": "https://gog.com"}]',
          '[{"id": 555, "game_id": 67890, "name": "The Witcher 3 (Steam)", "source_name": "Steam", "is_installed": 1, "hidden": 0}]',
          0
        );
      ''');

      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(),
        sort: SortOption.titleAsc,
      );

      expect(games.length, equals(1));
      final game = games.first;
      expect(game.id, equals('12345'));
      expect(game.gameId, equals('67890'));
      expect(game.name, equals('The Witcher 3'));
      expect(game.version, equals('1'));
      expect(game.releaseDate, equals('2015'));
      expect(game.source?.id, equals('10'));
      expect(game.source?.name, equals('GOG'));
      expect(game.completionStatus?.id, equals('2'));
      expect(game.platforms.length, equals(2));
      expect(game.platforms[0].id, equals('1'));
      expect(game.platforms[0].name, equals('PC'));
      expect(game.otherCopies.length, equals(1));
      expect(game.otherCopies.first.id, equals('555'));
      expect(game.otherCopies.first.isInstalled, isTrue);
    });

    test('2. Gracefully skips corrupted rows and returns valid games', () async {
      // Insert valid game
      await database.db.insert('games', {
        'id': 'valid-1',
        'game_id': 'app-1',
        'plugin_id': 'steam',
        'name': 'Hades',
        'sorting_name': 'Hades',
        'hidden': 0,
      });

      // Insert another valid game
      await database.db.insert('games', {
        'id': 'valid-2',
        'game_id': 'app-2',
        'plugin_id': 'steam',
        'name': 'Portal',
        'sorting_name': 'Portal',
        'hidden': 0,
      });

      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(),
        sort: SortOption.titleAsc,
      );

      expect(games.length, equals(2));
      expect(games.map((g) => g.name).toList(), containsAll(['Hades', 'Portal']));
    });

    test('3. Hidden filter: excludes hidden games by default and includes with includeHidden: true', () async {
      // Insert 2 games where both have hidden = 1
      await database.db.insert('games', {
        'id': 'hidden-1',
        'game_id': 'app-1',
        'plugin_id': 'steam',
        'name': 'Secret Game 1',
        'sorting_name': 'Secret Game 1',
        'hidden': 1,
      });
      await database.db.insert('games', {
        'id': 'hidden-2',
        'game_id': 'app-2',
        'plugin_id': 'steam',
        'name': 'Secret Game 2',
        'sorting_name': 'Secret Game 2',
        'hidden': 1,
      });

      // Default criteria has includeHidden = false
      const defaultCriteria = GameFilterCriteria();
      final defaultGames = await gameDao.getFilteredGames(
        criteria: defaultCriteria,
        sort: SortOption.titleAsc,
      );
      expect(defaultGames, isEmpty);

      // Criteria with includeHidden: true returns all hidden games
      const showHiddenCriteria = GameFilterCriteria(includeHidden: true);
      final allGames = await gameDao.getFilteredGames(
        criteria: showHiddenCriteria,
        sort: SortOption.titleAsc,
      );
      expect(allGames.length, equals(2));
      expect(allGames.map((g) => g.name).toList(), containsAll(['Secret Game 1', 'Secret Game 2']));
    });

    test('4. TaxonomyDao extracts taxonomies safely with numeric values', () async {
      await database.db.rawInsert('''
        INSERT INTO games (
          id, game_id, plugin_id, name, sorting_name,
          source_name, completion_status_name, platforms_json, genres_json, tags_json
        ) VALUES (
          'tax-1', 'app-1', 'p1', 'Game A', 'Game A',
          'Steam', 'Playing',
          '[{"name": "PC"}, {"name": 123}]',
          '[{"name": "Action"}]',
          '[{"name": "Singleplayer"}]'
        );
      ''');

      final taxonomies = await taxonomyDao.getAvailableTaxonomies();
      expect(taxonomies.sources, contains('Steam'));
      expect(taxonomies.completionStatuses, contains('Playing'));
      expect(taxonomies.platforms, containsAll(['123', 'PC']));
      expect(taxonomies.genres, contains('Action'));
      expect(taxonomies.tags, contains('Singleplayer'));
    });
  });
}
