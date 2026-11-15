import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/achievements_db_handler.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/addon_section_registry.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/achievements_section.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/fallback_addon_section.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    AddonSectionRegistry.reset();
  });

  group('Zero-Achievement UI Suppression Tests', () {
    const dummyGame = UnifiedGamePayload(
      id: 'game-dummy',
      gameId: 'app-dummy',
      pluginId: 'steam',
      name: 'Dummy Game',
      sortingName: 'Dummy Game',
    );

    testWidgets('1. buildSection returns SizedBox.shrink() when total == 0', (tester) async {
      const section = AchievementsSection();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'total': 0,
                  'unlocked': 0,
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('Achievements'), findsNothing);
    });

    testWidgets('2. buildSection returns SizedBox.shrink() when total_count == 0', (tester) async {
      const section = AchievementsSection(addonKey: 'playnite_achievements');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'total_count': 0,
                  'unlocked_count': 0,
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('3. buildSection returns SizedBox.shrink() when totalCount == 0', (tester) async {
      const section = AchievementsSection();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'totalCount': 0,
                  'unlockedCount': 0,
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('4. buildSection returns SizedBox.shrink() when has_achievements == false', (tester) async {
      const section = AchievementsSection();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'has_achievements': false,
                  'total': 50,
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('5. buildSection returns SizedBox.shrink() when items list is empty and no total specified', (tester) async {
      const section = AchievementsSection();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('5b. buildSection returns SizedBox.shrink() when total_count > 0 but items list is empty', (tester) async {
      const section = AchievementsSection();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widget = section.buildSection(
                context,
                {
                  'total_count': 5,
                  'unlocked_count': 2,
                  'items': [],
                },
                dummyGame,
              );
              return widget;
            },
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.textContaining('Achievements'), findsNothing);
    });

    testWidgets('6. AddonSectionRegistry suppresses empty achievement card in available sections list', (tester) async {
      const gameWithZeroAchievements = UnifiedGamePayload(
        id: 'game-zero',
        gameId: 'app-zero',
        pluginId: 'steam',
        name: 'Game With Zero Achievements',
        sortingName: 'Game With Zero Achievements',
        addons: {
          'playnite_achievements': {
            'total_count': 0,
            'unlocked_count': 0,
            'items': [],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithZeroAchievements);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Entire card should be suppressed
      expect(find.textContaining('Achievements'), findsNothing);
      expect(find.byType(Card), findsNothing);
      // Fallback section must NOT be rendered (not treated as unknown addon)
      expect(find.byType(FallbackAddonSection), findsNothing);
    });

    testWidgets('7. Renders achievements card for playnite_achievements when achievements exist', (tester) async {
      const gameWithPlayniteAchievements = UnifiedGamePayload(
        id: 'game-pa-positive',
        gameId: 'app-pa-pos',
        pluginId: 'gog',
        name: 'PA Positive Game',
        sortingName: 'PA Positive Game',
        addons: {
          'playnite_achievements': {
            'total_count': 2,
            'unlocked_count': 1,
            'items': [
              {
                'name': 'Glory Awaits',
                'description': 'Win your first battle',
                'unlocked': true,
                'rarity_percentage': 75.0,
              },
              {
                'name': 'Legend',
                'description': 'Beat the final boss',
                'unlocked': false,
                'rarity_percentage': 12.5,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithPlayniteAchievements);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Card is rendered with correct count
      expect(find.text('Achievements (1 / 2)'), findsOneWidget);
      expect(find.text('Glory Awaits'), findsOneWidget);
      expect(find.byType(FallbackAddonSection), findsNothing);
    });

    testWidgets('8. Renders achievements card for canonical achievements key when achievements exist', (tester) async {
      const gameWithCanonicalAchievements = UnifiedGamePayload(
        id: 'game-ca-positive',
        gameId: 'app-ca-pos',
        pluginId: 'steam',
        name: 'Canonical Positive Game',
        sortingName: 'Canonical Positive Game',
        addons: {
          'achievements': {
            'total': 1,
            'unlocked': 1,
            'items': [
              {
                'name': 'One and Only',
                'unlocked': true,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithCanonicalAchievements);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      expect(find.text('Achievements (1 / 1)'), findsOneWidget);
      expect(find.text('One and Only'), findsOneWidget);
    });

    testWidgets('9. Prioritizes playnite_achievements over success_story without duplicate cards', (tester) async {
      const gameWithBoth = UnifiedGamePayload(
        id: 'game-both',
        gameId: 'app-both',
        pluginId: 'steam',
        name: 'Dual Addons Game',
        sortingName: 'Dual Addons Game',
        addons: {
          'playnite_achievements': {
            'total_count': 1,
            'unlocked_count': 1,
            'items': [
              {
                'name': 'PA Specific Ach',
                'description': 'From playnite achievements',
                'unlocked': true,
              },
            ],
          },
          'success_story': {
            'total': 1,
            'unlocked': 1,
            'items': [
              {
                'name': 'SS Specific Ach',
                'description': 'From legacy success story',
                'unlocked': true,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithBoth);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      expect(find.text('PA Specific Ach'), findsOneWidget);
      expect(find.text('SS Specific Ach'), findsNothing);
      expect(find.text('Achievements (1 / 1)'), findsOneWidget);
    });

    testWidgets('10. Suppresses achievements if prioritized playnite_achievements is zero even when success_story has items', (tester) async {
      const gameWithZeroPAAndStaleSS = UnifiedGamePayload(
        id: 'game-zero-pa-stale-ss',
        gameId: 'app-zero-pa',
        pluginId: 'steam',
        name: 'Zero PA Game',
        sortingName: 'Zero PA Game',
        addons: {
          'playnite_achievements': {
            'total_count': 0,
            'unlocked_count': 0,
            'items': [],
          },
          'success_story': {
            'total': 1,
            'unlocked': 1,
            'items': [
              {
                'name': 'Stale SS Ach',
                'unlocked': true,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithZeroPAAndStaleSS);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('Achievements'), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Stale SS Ach'), findsNothing);
    });

    testWidgets('11. Renders achievement as unlocked when item has explicit is_unlocked: true and no date', (tester) async {
      const gameWithNoDateUnlocked = UnifiedGamePayload(
        id: 'game-no-date-unlocked',
        gameId: 'app-no-date',
        pluginId: 'gog',
        name: 'No Date Unlocked Game',
        sortingName: 'No Date Unlocked Game',
        addons: {
          'playnite_achievements': {
            'total_count': 1,
            'items': [
              {
                'name': 'Unlocked Without Date',
                'description': 'Unlocked by explicit boolean flag',
                'is_unlocked': true,
              },
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithNoDateUnlocked);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      expect(find.text('Achievements (1 / 1)'), findsOneWidget);
      expect(find.text('Unlocked Without Date'), findsOneWidget);
      expect(find.text('Unlocked'), findsOneWidget);
    });
  });

  group('AchievementsDbHandler Prioritization & Ingestion Tests', () {
    late AppDatabase database;
    late AchievementsDbHandler handler;

    setUp(() async {
      database = AppDatabase.instance;
      await database.init(inMemory: true);
      await database.reset();
      handler = AchievementsDbHandler();
    });

    tearDown(() async {
      await database.close();
    });

    test('Unpacks playnite_achievements over success_story when both exist in payload', () async {
      const payload = UnifiedGamePayload(
        id: 'db-game-both',
        gameId: 'app-both',
        pluginId: 'steam',
        name: 'DB Dual Addons Game',
        sortingName: 'DB Dual Addons Game',
        addons: {
          'playnite_achievements': {
            'total_count': 1,
            'unlocked_count': 1,
            'items': [
              {
                'api_name': 'PA_01',
                'name': 'PA Achievement',
                'unlocked': true,
              },
            ],
          },
          'success_story': {
            'total': 1,
            'unlocked': 1,
            'items': [
              {
                'api_name': 'SS_01',
                'name': 'SS Achievement',
                'unlocked': true,
              },
            ],
          },
        },
      );

      final batch = database.db.batch();
      await handler.unpack(payload, batch, database);
      await batch.commit(noResult: true);

      final rows = await database.db.query(
        'achievements',
        where: 'game_id = ?',
        whereArgs: ['db-game-both'],
      );

      expect(rows.length, equals(1));
      expect(rows.first['api_name'], equals('PA_01'));
      expect(rows.first['name'], equals('PA Achievement'));
    });

    test('Marks item with explicit unlocked: true or is_unlocked: true as unlocked in SQLite even if date is missing', () async {
      const payload = UnifiedGamePayload(
        id: 'db-game-boolean-flags',
        gameId: 'app-flags',
        pluginId: 'gog',
        name: 'Boolean Flags Game',
        sortingName: 'Boolean Flags Game',
        addons: {
          'playnite_achievements': {
            'total_count': 3,
            'items': [
              {
                'api_name': 'FLAG_UNLOCKED',
                'name': 'Unlocked by Flag',
                'unlocked': true,
              },
              {
                'api_name': 'FLAG_IS_UNLOCKED',
                'name': 'Unlocked by IsUnlocked Flag',
                'is_unlocked': true,
              },
              {
                'api_name': 'FLAG_LOCKED',
                'name': 'Locked Item',
                'unlocked': false,
              },
            ],
          },
        },
      );

      final batch = database.db.batch();
      await handler.unpack(payload, batch, database);
      await batch.commit(noResult: true);

      final rows = await database.db.query(
        'achievements',
        where: 'game_id = ?',
        whereArgs: ['db-game-boolean-flags'],
        orderBy: 'api_name ASC',
      );

      expect(rows.length, equals(3));

      // FLAG_IS_UNLOCKED
      expect(rows[0]['api_name'], equals('FLAG_IS_UNLOCKED'));
      expect(rows[0]['date_unlocked_utc'], isNotNull);

      // FLAG_LOCKED
      expect(rows[1]['api_name'], equals('FLAG_LOCKED'));
      expect(rows[1]['date_unlocked_utc'], isNull);

      // FLAG_UNLOCKED
      expect(rows[2]['api_name'], equals('FLAG_UNLOCKED'));
      expect(rows[2]['date_unlocked_utc'], isNotNull);
    });

    test('Zero-achievement payload wipes previous achievements from database', () async {
      const initialPayload = UnifiedGamePayload(
        id: 'db-game-wiping',
        gameId: 'app-wipe',
        pluginId: 'steam',
        name: 'Wipe Test Game',
        sortingName: 'Wipe Test Game',
        addons: {
          'playnite_achievements': {
            'total_count': 1,
            'items': [
              {
                'api_name': 'WILL_BE_WIPED',
                'name': 'Temporary Achievement',
                'unlocked': true,
              },
            ],
          },
        },
      );

      final batch1 = database.db.batch();
      await handler.unpack(initialPayload, batch1, database);
      await batch1.commit(noResult: true);

      final rowsBefore = await database.db.query('achievements', where: 'game_id = ?', whereArgs: ['db-game-wiping']);
      expect(rowsBefore.length, equals(1));

      const zeroPayload = UnifiedGamePayload(
        id: 'db-game-wiping',
        gameId: 'app-wipe',
        pluginId: 'steam',
        name: 'Wipe Test Game',
        sortingName: 'Wipe Test Game',
        addons: {
          'playnite_achievements': {
            'total_count': 0,
            'items': [],
          },
        },
      );

      final batch2 = database.db.batch();
      await handler.unpack(zeroPayload, batch2, database);
      await batch2.commit(noResult: true);

      final rowsAfter = await database.db.query('achievements', where: 'game_id = ?', whereArgs: ['db-game-wiping']);
      expect(rowsAfter, isEmpty);
    });
  });
}
