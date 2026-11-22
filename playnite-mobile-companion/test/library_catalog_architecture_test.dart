import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/library_catalog.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late GameDao gameDao;
  late LibraryCatalog catalog;

  const testGames = [
    UnifiedGamePayload(
      id: 'g-witcher3',
      gameId: 'app-w3',
      pluginId: 'steam',
      name: 'The Witcher 3: Wild Hunt',
      sortingName: 'Witcher 3: Wild Hunt, The',
      developers: [NamedItem(id: 'cdpr', name: 'CD Projekt RED')],
      publishers: [NamedItem(id: 'cdpr', name: 'CD Projekt')],
      genres: [NamedItem(id: 'rpg', name: 'RPG')],
      tags: [NamedItem(id: 'openworld', name: 'Open World')],
      playtimeSeconds: 360000,
    ),
    UnifiedGamePayload(
      id: 'g-cyberpunk',
      gameId: 'app-cp',
      pluginId: 'gog',
      name: 'Cyberpunk 2077',
      sortingName: 'Cyberpunk 2077',
      developers: [NamedItem(id: 'cdpr', name: 'CD Projekt RED')],
      genres: [NamedItem(id: 'rpg', name: 'RPG'), NamedItem(id: 'action', name: 'Action')],
      description: 'Futuristic sci-fi open world adventure.',
      playtimeSeconds: 180000,
    ),
    UnifiedGamePayload(
      id: 'g-eternum',
      gameId: 'app-et',
      pluginId: 'itch',
      name: 'Eternum',
      sortingName: 'Eternum',
      playtimeSeconds: 7200,
    ),
    UnifiedGamePayload(
      id: 'g-silksong',
      gameId: 'app-ss',
      pluginId: 'steam',
      name: 'Hollow Knight: Silksong',
      sortingName: 'Hollow Knight: Silksong',
      playtimeSeconds: 0,
    ),
    UnifiedGamePayload(
      id: 'g-hades',
      gameId: 'app-hades',
      pluginId: 'steam',
      name: 'Hades',
      sortingName: 'Hades',
      genres: [NamedItem(id: 'roguelike', name: 'Roguelike')],
      playtimeSeconds: 90000,
    ),
  ];

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);
    catalog = LibraryCatalog(database);

    await gameDao.batchUpsertGames(testGames);
  });

  tearDown(() async {
    await database.close();
  });

  group('Library Catalog & Candidate Pruning Architecture Tests', () {
    test('1. Cleanly eliminates dead games_fts virtual table from schema', () async {
      final ftsTableCheck = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name = 'games_fts';",
      );
      expect(ftsTableCheck, isEmpty);

      // Verify index on games(name) exists
      final nameIndexCheck = await database.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_games_name';",
      );
      expect(nameIndexCheck, isNotEmpty);
    });

    test('2. Direct search candidate pruning in SQLite retrieves matching titles', () async {
      final results = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'Witcher'),
        sort: SortOption.titleAsc,
      );

      expect(results.length, equals(1));
      expect(results.first.name, equals('The Witcher 3: Wild Hunt'));
    });

    test('3. Multi-word search candidate pruning matches token conjunction in SQLite', () async {
      final results = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'witcher wild hunt'),
        sort: SortOption.titleAsc,
      );

      expect(results.length, equals(1));
      expect(results.first.name, equals('The Witcher 3: Wild Hunt'));
    });

    test('4. Metadata search candidate pruning matches developers and description', () async {
      final cdprResults = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'CD Projekt RED'),
        sort: SortOption.titleAsc,
      );

      expect(cdprResults.length, equals(2));
      final names = cdprResults.map((g) => g.name).toList();
      expect(names, containsAll(['The Witcher 3: Wild Hunt', 'Cyberpunk 2077']));

      final descResults = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'Futuristic sci-fi'),
        sort: SortOption.titleAsc,
      );
      expect(descResults.length, equals(1));
      expect(descResults.first.name, equals('Cyberpunk 2077'));
    });

    test('5. Typo-tolerant candidate fallback finds "Eternum" for "Eternm"', () async {
      final results = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'Eternm'),
        sort: SortOption.titleAsc,
      );

      expect(results.length, equals(1));
      expect(results.first.name, equals('Eternum'));
    });

    test('6. Typo-tolerant candidate fallback finds "Hollow Knight: Silksong" for "Silksongg"', () async {
      final results = await catalog.getGames(
        criteria: const GameFilterCriteria(searchQuery: 'Silksongg'),
        sort: SortOption.titleAsc,
      );

      expect(results.length, equals(1));
      expect(results.first.name, equals('Hollow Knight: Silksong'));
    });

    test('7. Fast getGamesCount uses direct SQLite COUNT(*) with search criteria', () async {
      final count = await catalog.getGamesCount(
        criteria: const GameFilterCriteria(searchQuery: 'CD Projekt RED'),
      );
      expect(count, equals(2));

      final typoCount = await catalog.getGamesCount(
        criteria: const GameFilterCriteria(searchQuery: 'Eternm'),
      );
      expect(typoCount, equals(1));

      final emptyCount = await catalog.getGamesCount(
        criteria: const GameFilterCriteria(searchQuery: 'NonExistentTitleXYZ'),
      );
      expect(emptyCount, equals(0));
    });

    test('8. watchGames reactive live streaming emits initial list and updates on mutations', () async {
      final emittedLists = <List<UnifiedGamePayload>>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final sub = catalog
          .watchGames(
            criteria: const GameFilterCriteria(),
            sort: SortOption.titleAsc,
          )
          .listen((list) {
            emittedLists.add(list);
            if (emittedLists.length == 1 && !completer1.isCompleted) {
              completer1.complete();
            } else if (emittedLists.length == 2 && !completer2.isCompleted) {
              completer2.complete();
            }
          });

      await completer1.future;
      expect(emittedLists.first.length, equals(5));

      // Ingest a new game via batchUpsertGames
      const newGame = UnifiedGamePayload(
        id: 'g-new',
        gameId: 'app-new',
        pluginId: 'steam',
        name: 'A New Adventure',
        sortingName: 'New Adventure, A',
      );
      await gameDao.batchUpsertGames([newGame]);

      await completer2.future;
      expect(emittedLists.last.length, equals(6));
      expect(emittedLists.last.any((g) => g.id == 'g-new'), isTrue);

      await sub.cancel();
    });

    test('9. watchGamesCount reactive live streaming emits initial count and updates on delete', () async {
      final emittedCounts = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final sub = catalog
          .watchGamesCount(
            criteria: const GameFilterCriteria(),
          )
          .listen((count) {
            emittedCounts.add(count);
            if (emittedCounts.length == 1 && !completer1.isCompleted) {
              completer1.complete();
            } else if (emittedCounts.length == 2 && !completer2.isCompleted) {
              completer2.complete();
            }
          });

      await completer1.future;
      expect(emittedCounts.first, equals(5));

      // Delete one game
      await gameDao.batchDeleteGames(['g-hades']);

      await completer2.future;
      expect(emittedCounts.last, equals(4));

      await sub.cancel();
    });
  });
}
