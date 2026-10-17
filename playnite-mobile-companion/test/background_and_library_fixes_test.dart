import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/services/background_sync_service.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/library/presentation/library_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/widgets/sync_dialog.dart';
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
    await database.reset();
    gameDao = GameDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('BackgroundSyncService Tests', () {
    test('BackgroundSyncService safe execution on non-Android platform without throwing', () async {
      final wakeLockAcquired = await BackgroundSyncService.acquireWakeLock();
      expect(wakeLockAcquired, isA<bool>());

      final wakeLockReleased = await BackgroundSyncService.releaseWakeLock();
      expect(wakeLockReleased, isA<bool>());

      final isIgnoring = await BackgroundSyncService.isIgnoringBatteryOptimizations();
      expect(isIgnoring, isA<bool>());

      final reqResult = await BackgroundSyncService.requestIgnoreBatteryOptimizations();
      expect(reqResult, isA<bool>());

      final openResult = await BackgroundSyncService.openBatteryOptimizationSettings();
      expect(openResult, isA<bool>());
    });
  });

  group('GameDao NULL hidden column Handling Tests', () {
    test('Game with NULL hidden column is retrieved when includeHidden is false', () async {
      // Recreate table with nullable hidden column to simulate legacy/external databases
      await database.db.execute('DROP TABLE games;');
      await database.db.execute('''
        CREATE TABLE games (
          id TEXT PRIMARY KEY,
          game_id TEXT NOT NULL,
          plugin_id TEXT NOT NULL,
          name TEXT NOT NULL,
          sorting_name TEXT NOT NULL,
          hidden INTEGER
        );
      ''');

      await database.db.rawInsert('''
        INSERT INTO games (id, game_id, plugin_id, name, sorting_name, hidden)
        VALUES ('game-null-hidden', 'g-1', 'p-1', 'Witcher 3', 'Witcher 3', NULL);
      ''');

      final games = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(includeHidden: false),
        sort: SortOption.titleAsc,
      );

      expect(games.length, equals(1));
      expect(games.first.name, equals('Witcher 3'));
      expect(games.first.hidden, isFalse);
    });

    test('Game with hidden = 1 is excluded by default but included with includeHidden: true', () async {
      await database.db.rawInsert('''
        INSERT INTO games (id, game_id, plugin_id, name, sorting_name, hidden)
        VALUES ('game-hidden-1', 'g-2', 'p-2', 'Secret Game', 'Secret Game', 1);
      ''');

      final excluded = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(includeHidden: false),
        sort: SortOption.titleAsc,
      );
      expect(excluded, isEmpty);

      final included = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(includeHidden: true),
        sort: SortOption.titleAsc,
      );
      expect(included.length, equals(1));
      expect(included.first.name, equals('Secret Game'));
      expect(included.first.hidden, isTrue);
    });
  });

  group('SyncDialog Completion Notification Tests', () {
    testWidgets('SyncDialog calls onSyncCompleted on close or completion', (tester) async {
      bool syncCompletedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncDialog(
              database: database,
              onSyncCompleted: () {
                syncCompletedCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Close button
      final closeButton = find.text('Close');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // onSyncCompleted must be invoked
      expect(syncCompletedCalled, isTrue);
    });
  });

  group('LibraryScreen Empty State & Filter Reset Tests', () {
    testWidgets('Shows "Welcome to Playnite Companion" only when DB has 0 games', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: LibraryScreen(database: database),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();

      expect(find.text('Welcome to Playnite Companion'), findsOneWidget);
      expect(find.text('Configure Sync & Google Drive'), findsOneWidget);
      expect(find.text('Sync Library Now'), findsOneWidget);
    });

    testWidgets('Shows "No games match your current filters" when DB has games but query matches 0', (tester) async {
      await tester.runAsync(() async {
        // Seed 1 hidden game in database (so DB has 1 game, but default filter with includeHidden: false matches 0)
        await gameDao.batchUpsertGames([
          const UnifiedGamePayload(
            id: 'test-game-1',
            gameId: 'app-1',
            pluginId: 'p-1',
            name: 'Secret Game',
            sortingName: 'Secret Game',
            hidden: true,
          ),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: LibraryScreen(database: database),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });

      await tester.pump();

      // Must NOT show the onboarding card because DB has 1 game!
      expect(find.text('Welcome to Playnite Companion'), findsNothing);
      expect(find.text('Configure Sync & Google Drive'), findsNothing);

      // Must show the filtered empty state with reset button
      expect(find.text('No games match your current filters'), findsOneWidget);
      expect(find.text('Reset Filters & Show All 1 Games'), findsOneWidget);

      // Tapping reset button resets filters and reveals the game!
      final textFinder = find.text('Reset Filters & Show All 1 Games');
      expect(textFinder, findsOneWidget);
      final buttonFinder = find.ancestor(of: textFinder, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<ElevatedButton>(buttonFinder);
      button.onPressed?.call();

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Secret Game'), findsAtLeastNWidgets(1));
    });
  });
}
