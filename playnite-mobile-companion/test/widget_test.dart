import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/game_card_grid.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();

    // Insert 1 test game
    final gameDao = GameDao(database);
    await gameDao.batchUpsertGames([
      const UnifiedGamePayload(
        id: 'test-1',
        gameId: 'app-1',
        pluginId: 'p1',
        name: 'Cyberpunk 2077',
        sortingName: 'Cyberpunk 2077',
        playtimeSeconds: 72000,
        isInstalled: true,
        source: NamedItem(id: 'steam', name: 'Steam'),
      ),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('PlayniteCompanionApp smoke test: loads LibraryScreen and shows seeded game', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: PlayniteCompanionApp(database: database),
        ),
      );
      // Allow SQLite FFI isolate query to complete
      await Future.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();

    // Verify AppBar title is present
    expect(find.text('Playnite'), findsOneWidget);

    // Verify GameCardGrid is rendered
    expect(find.byType(GameCardGrid), findsOneWidget);
    expect(find.text('Cyberpunk 2077'), findsAtLeastNWidgets(1));
  });
}
