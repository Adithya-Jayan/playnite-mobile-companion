import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
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
  late StatsDao statsDao;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);
    taxonomyDao = TaxonomyDao(database);
    statsDao = StatsDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('Database, Normalization & Filtering Tests', () {
    test('Batch upsert normalizes child tables while preserving addonsJson container', () async {
      final game = UnifiedGamePayload(
        id: 'cyberpunk-guid',
        gameId: '1091500',
        pluginId: 'steam-plugin',
        name: 'Cyberpunk 2077',
        sortingName: 'Cyberpunk 2077',
        playtimeSeconds: 756000,
        playCount: 42,
        isInstalled: true,
        favorite: true,
        userScore: 92,
        source: const NamedItem(id: 'steam', name: 'Steam'),
        completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
        platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
        genres: const [NamedItem(id: 'rpg', name: 'RPG')],
        addons: {
          'how_long_to_beat': {
            'main_story_seconds': 93600,
            'main_extra_seconds': 216000,
            'completionist_seconds': 374400,
          },
          'success_story': {
            'achievements': [
              {
                'api_name': 'ach_1',
                'name': 'The World',
                'description': 'Main story',
                'date_unlocked_utc': '2025-06-12T18:30:00Z',
                'percent': 35.0,
                'gamer_score': 50.0,
              },
            ],
          },
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': '2025-06-12T19:00:00Z',
                'elapsed_seconds': 3600,
                'action_name': 'Play',
              },
            ],
          },
          'check_dlc': {
            'dlcs': [
              {
                'dlc_id': 'dlc_1',
                'name': 'Phantom Liberty',
                'is_owned': true,
                'price': 29.99,
              },
            ],
          },
          'custom_ext': {'level': 'expert'},
        },
      );

      await gameDao.batchUpsertGames([game]);

      // 1. Verify primary game row and raw addons_json container
      final fetched = await gameDao.getGameById('cyberpunk-guid');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Cyberpunk 2077'));
      expect(fetched.addons.containsKey('custom_ext'), isTrue);
      expect(fetched.addons['custom_ext']['level'], equals('expert'));

      // 2. Verify child table normalization in SQLite
      final db = database.db;
      final achRows = await db.query('achievements', where: 'game_id = ?', whereArgs: ['cyberpunk-guid']);
      expect(achRows.length, equals(1));
      expect(achRows.first['name'], equals('The World'));

      final sessionRows = await db.query('play_sessions', where: 'game_id = ?', whereArgs: ['cyberpunk-guid']);
      expect(sessionRows.length, equals(1));
      expect(sessionRows.first['elapsed_seconds'], equals(3600));

      final hltbRows = await db.query('hltb_data', where: 'game_id = ?', whereArgs: ['cyberpunk-guid']);
      expect(hltbRows.length, equals(1));
      expect(hltbRows.first['main_story_seconds'], equals(93600));

      final dlcRows = await db.query('dlc_items', where: 'game_id = ?', whereArgs: ['cyberpunk-guid']);
      expect(dlcRows.length, equals(1));
      expect(dlcRows.first['name'], equals('Phantom Liberty'));
    });

    test('Multi-criteria Filtering & Sorting across library', () async {
      final games = [
        UnifiedGamePayload(
          id: 'g1',
          gameId: 's1',
          pluginId: 'p',
          name: 'The Witcher 3',
          sortingName: 'Witcher 3, The',
          playtimeSeconds: 360000, // 100h
          userScore: 96,
          isInstalled: true,
          favorite: true,
          source: const NamedItem(id: 'steam', name: 'Steam'),
          completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
          platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
          genres: const [NamedItem(id: 'rpg', name: 'RPG')],
        ),
        UnifiedGamePayload(
          id: 'g2',
          gameId: 's2',
          pluginId: 'p',
          name: 'Elden Ring',
          sortingName: 'Elden Ring',
          playtimeSeconds: 540000, // 150h
          userScore: 95,
          isInstalled: false,
          favorite: true,
          source: const NamedItem(id: 'steam', name: 'Steam'),
          completionStatus: const NamedItem(id: 'beaten', name: 'Beaten'),
          platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
          genres: const [NamedItem(id: 'rpg', name: 'RPG'), NamedItem(id: 'action', name: 'Action')],
        ),
        UnifiedGamePayload(
          id: 'g3',
          gameId: 's3',
          pluginId: 'p',
          name: 'Hades',
          sortingName: 'Hades',
          playtimeSeconds: 72000, // 20h
          userScore: 93,
          isInstalled: true,
          favorite: false,
          source: const NamedItem(id: 'epic', name: 'Epic Games'),
          completionStatus: const NamedItem(id: 'playing', name: 'Playing'),
          platforms: const [NamedItem(id: 'switch', name: 'Nintendo Switch')],
          genres: const [NamedItem(id: 'action', name: 'Action')],
        ),
      ];

      await gameDao.batchUpsertGames(games);

      // Filter: Installed only
      final installedOnly = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(isInstalled: true),
        sort: SortOption.titleAsc,
      );
      expect(installedOnly.length, equals(2));
      expect(installedOnly.map((g) => g.name), containsAll(['The Witcher 3', 'Hades']));

      // Filter: Source = Steam
      final steamOnly = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(sources: {'Steam'}),
        sort: SortOption.titleAsc,
      );
      expect(steamOnly.length, equals(2));
      expect(steamOnly.map((g) => g.name), containsAll(['The Witcher 3', 'Elden Ring']));

      // Filter: Genre = Action
      final actionOnly = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(genres: {'Action'}),
        sort: SortOption.titleAsc,
      );
      expect(actionOnly.length, equals(2));
      expect(actionOnly.map((g) => g.name), containsAll(['Elden Ring', 'Hades']));

      // Search Query: "Witcher"
      final searchResults = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Witcher'),
        sort: SortOption.titleAsc,
      );
      expect(searchResults.length, equals(1));
      expect(searchResults.first.name, equals('The Witcher 3'));

      // Sort: Playtime descending
      final byPlaytime = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(),
        sort: SortOption.playtimeDesc,
      );
      expect(byPlaytime.first.name, equals('Elden Ring'));
      expect(byPlaytime[1].name, equals('The Witcher 3'));
      expect(byPlaytime[2].name, equals('Hades'));

      // Taxonomies
      final taxonomies = await taxonomyDao.getAvailableTaxonomies();
      expect(taxonomies.sources, containsAll(['Steam', 'Epic Games']));
      expect(taxonomies.genres, containsAll(['RPG', 'Action']));
      expect(taxonomies.platforms, containsAll(['PC (Windows)', 'Nintendo Switch']));

      // Stats Calculation
      final stats = await statsDao.calculateLibraryStats();
      expect(stats.totalGames, equals(3));
      expect(stats.installedCount, equals(2));
      expect(stats.favoritesCount, equals(2));
      expect(stats.totalPlaytimeSeconds, equals(360000 + 540000 + 72000));
      expect(stats.completionBreakdown['Completed'], equals(1));
      expect(stats.completionBreakdown['Beaten'], equals(1));
      expect(stats.completionBreakdown['Playing'], equals(1));
    });
  });
}
