import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/features/sync/data/demo_library_data.dart';
import 'package:playnite_mobile_companion/main.dart';
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

  group('seedInitialLibrary Seeding Delegation Tests', () {
    test('seedInitialLibrary populates database using DemoLibraryData.getDemoGames()', () async {
      expect(await gameDao.getGamesCount(), equals(0));

      await seedInitialLibrary(gameDao, syncMetaDao);

      final demoGames = DemoLibraryData.getDemoGames();
      expect(await gameDao.getGamesCount(), equals(demoGames.length));

      for (final demoGame in demoGames) {
        final loadedGame = await gameDao.getGameById(demoGame.id);
        expect(loadedGame, isNotNull);
        expect(loadedGame!.name, equals(demoGame.name));
      }

      final syncEntries = await syncMetaDao.getAllEntriesMap();
      expect(syncEntries.length, equals(demoGames.length));
      for (final demoGame in demoGames) {
        final path = 'games/${demoGame.id}.json';
        expect(syncEntries.containsKey(path), isTrue);
        expect(syncEntries[path]!.gameId, equals(demoGame.id));
      }
    });
  });
}
