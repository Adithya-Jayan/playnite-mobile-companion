import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/filter_drawer.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/game_list_tile.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
  });

  tearDown(() async {
    await database.close();
  });

  group('Ticket #31: Filter Drawer Contrast Tests', () {
    testWidgets('Selected ChoiceChip in Utility & Diagnostics uses high-contrast white text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            endDrawer: FilterDrawer(
              currentCriteria: const GameFilterCriteria(
                utilityMode: UtilityFilterMode.onlyHidden,
              ),
              taxonomies: const FilterTaxonomies(),
              onApply: (_) {},
              onReset: () {},
            ),
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openEndDrawer();
      await tester.pumpAndSettle();

      // Find 'Only Hidden' ChoiceChip
      final onlyHiddenFinder = find.widgetWithText(ChoiceChip, 'Only Hidden');
      expect(onlyHiddenFinder, findsOneWidget);

      final chipWidget = tester.widget<ChoiceChip>(onlyHiddenFinder);
      expect(chipWidget.selected, isTrue);
      expect(chipWidget.selectedColor, equals(AppTheme.primary));
      expect(chipWidget.labelStyle?.color, equals(Colors.white));
      expect(chipWidget.checkmarkColor, equals(Colors.white));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Ticket #31: GameListTile Score Badge & Tooltip Tests', () {
    testWidgets('GameListTile renders star icon, formatted percentage, and score tooltip', (tester) async {
      const game = UnifiedGamePayload(
        id: 'g-score-test',
        gameId: 'g-score-test',
        pluginId: 'steam',
        name: 'The Witcher 3',
        sortingName: 'Witcher 3',
        userScore: 92,
        communityScore: 89,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: GameListTile(
              game: game,
              ratingScoreSource: RatingScoreSource.user,
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify star icon is displayed
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);

      // Verify score text '92%' is displayed
      expect(find.text('92%'), findsOneWidget);

      // Verify Tooltip exists with User Score
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsWidgets);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text('92%'), matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, equals('User Score: 92%'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('GameListTile community score fallback when user score is null', (tester) async {
      const game = UnifiedGamePayload(
        id: 'g-score-comm',
        gameId: 'g-score-comm',
        pluginId: 'steam',
        name: 'Portal',
        sortingName: 'Portal',
        communityScore: 95,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: GameListTile(
              game: game,
              ratingScoreSource: RatingScoreSource.composite,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text('95%'), matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, equals('Community Score: 95%'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Ticket #31: SyncSettingsScreen Last Synced Timestamp Tests', () {
    testWidgets('Displays formatted last sync timestamp when lastSyncUtc is set', (tester) async {
      await tester.runAsync(() async {
        final repo = SyncConfigRepository(database);
        await repo.saveConfig(const SyncConfiguration(
          lastSyncUtc: '2026-11-21T13:00:00Z',
        ));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SyncSettingsScreen(database: database),
        ),
      );

      // Allow settings to load through FFI isolate
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.textContaining('Last Synced: Nov 21, 2026'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Displays "Never synced" when lastSyncUtc is null or empty', (tester) async {
      await tester.runAsync(() async {
        final repo = SyncConfigRepository(database);
        await repo.saveConfig(const SyncConfiguration(
          lastSyncUtc: null,
        ));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SyncSettingsScreen(database: database),
        ),
      );

      // Allow settings to load through FFI isolate
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('Never synced'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
