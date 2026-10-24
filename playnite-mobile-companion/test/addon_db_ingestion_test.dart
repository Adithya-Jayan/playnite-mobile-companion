import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/achievements_db_handler.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/addon_db_registry.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/i_addon_db_handler.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/sessions_db_handler.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CustomTestDbHandler implements IAddonDbHandler {
  bool unpackCalled = false;
  String? lastGameId;

  @override
  String get addonKey => 'custom_test_addon';

  @override
  Future<void> unpack(UnifiedGamePayload payload, Batch batch, AppDatabase database) async {
    if (payload.addons.containsKey(addonKey)) {
      unpackCalled = true;
      lastGameId = payload.id;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late GameDao gameDao;

  setUp(() async {
    AddonDbRegistry.reset();
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    gameDao = GameDao(database);
  });

  tearDown(() async {
    AddonDbRegistry.reset();
    await database.close();
  });

  group('Decoupled Addon DB Ingestion Tests', () {
    test('1. Default registry registers AchievementsDbHandler and SessionsDbHandler', () {
      final handlers = AddonDbRegistry.handlers;
      expect(handlers.length, equals(2));
      expect(handlers.any((h) => h is AchievementsDbHandler), isTrue);
      expect(handlers.any((h) => h is SessionsDbHandler), isTrue);
    });

    test('2. Unpacks legacy success_story achievements into achievements SQLite table', () async {
      const payload = UnifiedGamePayload(
        id: 'game-success-story',
        gameId: 'app-1',
        pluginId: 'steam',
        name: 'Success Story Game',
        sortingName: 'Success Story Game',
        addons: {
          'success_story': {
            'total': 2,
            'unlocked': 1,
            'items': [
              {
                'api_name': 'ACH_001',
                'name': 'First Blood',
                'description': 'Defeat the first boss',
                'url_unlocked': 'media/ach_001.png',
                'url_locked': 'media/ach_001_lock.png',
                'date_unlocked_utc': '2024-01-15T12:00:00Z',
                'percent': 45.5,
                'gamerscore': 15.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_002',
                'name': 'Secret Master',
                'description': 'Find all secrets',
                'url_unlocked': 'media/ach_002.png',
                'url_locked': 'media/ach_002_lock.png',
                'date_unlocked_utc': null,
                'percent': 5.2,
                'gamerscore': 50.0,
                'is_hidden': true,
              },
            ],
          },
        },
      );

      await gameDao.batchUpsertGames([payload]);

      final rows = await database.db.query(
        'achievements',
        where: 'game_id = ?',
        whereArgs: ['game-success-story'],
        orderBy: 'api_name ASC',
      );

      expect(rows.length, equals(2));
      expect(rows[0]['api_name'], equals('ACH_001'));
      expect(rows[0]['name'], equals('First Blood'));
      expect(rows[0]['url_unlocked'], equals('media/ach_001.png'));
      expect(rows[0]['percent'], equals(45.5));
      expect(rows[0]['gamer_score'], equals(15.0));
      expect(rows[0]['is_hidden'], equals(0));

      expect(rows[1]['api_name'], equals('ACH_002'));
      expect(rows[1]['name'], equals('Secret Master'));
      expect(rows[1]['is_hidden'], equals(1));
    });

    test('3. Unpacks modern playnite_achievements payload into achievements SQLite table', () async {
      const payload = UnifiedGamePayload(
        id: 'game-playnite-achievements',
        gameId: 'app-pa',
        pluginId: 'gog',
        name: 'GOG Game PA',
        sortingName: 'GOG Game PA',
        addons: {
          'playnite_achievements': {
            'total_count': 1,
            'unlocked_count': 1,
            'items': [
              {
                'apiName': 'PA_CHAMPION',
                'name': 'World Champion',
                'description': 'Win tournament',
                'icon_unlocked': 'media/pa_champ.png',
                'icon_locked': 'media/pa_champ_lock.png',
                'date_unlocked': '2024-02-10T14:30:00Z',
                'rarity_percentage': 1.8,
                'gamerScore': 100,
                'isHidden': false,
              },
            ],
          },
        },
      );

      await gameDao.batchUpsertGames([payload]);

      final rows = await database.db.query(
        'achievements',
        where: 'game_id = ?',
        whereArgs: ['game-playnite-achievements'],
      );

      expect(rows.length, equals(1));
      expect(rows.first['api_name'], equals('PA_CHAMPION'));
      expect(rows.first['name'], equals('World Champion'));
      expect(rows.first['url_unlocked'], equals('media/pa_champ.png'));
      expect(rows.first['percent'], equals(1.8));
      expect(rows.first['gamer_score'], equals(100.0));
    });

    test('4. Unpacks canonical achievements key payload into achievements SQLite table', () async {
      const payload = UnifiedGamePayload(
        id: 'game-canonical-achievements',
        gameId: 'app-ca',
        pluginId: 'steam',
        name: 'Canonical Game',
        sortingName: 'Canonical Game',
        addons: {
          'achievements': {
            'total': 1,
            'items': [
              {
                'api_name': 'CANON_01',
                'name': 'First Step',
                'description': 'Start game',
                'percent': 99.0,
              },
            ],
          },
        },
      );

      await gameDao.batchUpsertGames([payload]);

      final rows = await database.db.query(
        'achievements',
        where: 'game_id = ?',
        whereArgs: ['game-canonical-achievements'],
      );

      expect(rows.length, equals(1));
      expect(rows.first['api_name'], equals('CANON_01'));
      expect(rows.first['percent'], equals(99.0));
    });

    test('5. Unpacks game_activity sessions into play_sessions SQLite table', () async {
      const payload = UnifiedGamePayload(
        id: 'game-sessions',
        gameId: 'app-sess',
        pluginId: 'steam',
        name: 'Session Game',
        sortingName: 'Session Game',
        addons: {
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': '2024-03-01T10:00:00Z',
                'elapsed_seconds': 3600,
                'action_name': 'Main Story Session',
              },
              {
                'date_session_utc': '2024-03-02T15:00:00Z',
                'elapsed_seconds': 1800,
                'action_name': 'Side Quests',
              },
            ],
          },
        },
      );

      await gameDao.batchUpsertGames([payload]);

      final rows = await database.db.query(
        'play_sessions',
        where: 'game_id = ?',
        whereArgs: ['game-sessions'],
        orderBy: 'date_session_utc ASC',
      );

      expect(rows.length, equals(2));
      expect(rows[0]['date_session_utc'], equals('2024-03-01T10:00:00Z'));
      expect(rows[0]['elapsed_seconds'], equals(3600));
      expect(rows[0]['action_name'], equals('Main Story Session'));

      expect(rows[1]['date_session_utc'], equals('2024-03-02T15:00:00Z'));
      expect(rows[1]['elapsed_seconds'], equals(1800));
      expect(rows[1]['action_name'], equals('Side Quests'));
    });

    test('6. Empty achievements list wipes previous achievement rows from database', () async {
      // Step 1: Ingest game with achievements
      const payloadWithAchievements = UnifiedGamePayload(
        id: 'game-wiping',
        gameId: 'app-wipe',
        pluginId: 'steam',
        name: 'Wiping Game',
        sortingName: 'Wiping Game',
        addons: {
          'success_story': {
            'total': 1,
            'items': [
              {'api_name': 'A1', 'name': 'Old Achievement'},
            ],
          },
        },
      );
      await gameDao.batchUpsertGames([payloadWithAchievements]);
      final count = await database.db.query('achievements', where: 'game_id = ?', whereArgs: ['game-wiping']);
      expect(count.length, equals(1));

      // Step 2: Ingest update with empty achievements list
      const payloadZeroAchievements = UnifiedGamePayload(
        id: 'game-wiping',
        gameId: 'app-wipe',
        pluginId: 'steam',
        name: 'Wiping Game',
        sortingName: 'Wiping Game',
        addons: {
          'success_story': {
            'total': 0,
            'items': [],
          },
        },
      );
      await gameDao.batchUpsertGames([payloadZeroAchievements]);

      final updatedRows = await database.db.query('achievements', where: 'game_id = ?', whereArgs: ['game-wiping']);
      expect(updatedRows, isEmpty);
    });

    test('7. Custom registered IAddonDbHandler executes during GameDao.batchUpsertGames', () async {
      final customHandler = _CustomTestDbHandler();
      AddonDbRegistry.register(customHandler);

      const payload = UnifiedGamePayload(
        id: 'game-custom-addon',
        gameId: 'app-cust',
        pluginId: 'custom',
        name: 'Custom Addon Game',
        sortingName: 'Custom Addon Game',
        addons: {
          'custom_test_addon': {
            'meta': 'some_val',
          },
        },
      );

      await gameDao.batchUpsertGames([payload]);

      expect(customHandler.unpackCalled, isTrue);
      expect(customHandler.lastGameId, equals('game-custom-addon'));
    });
  });
}
