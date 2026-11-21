import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/global_achievements_browser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase database;
  late StatsDao statsDao;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    statsDao = StatsDao(database);

    // Seed games
    await database.db.insert('games', {
      'id': 'game-alpha',
      'game_id': 'game-alpha',
      'plugin_id': 'steam',
      'name': 'Alpha Protocol',
      'sorting_name': 'Alpha Protocol',
      'playtime_seconds': 10000,
    });

    await database.db.insert('games', {
      'id': 'game-zeta',
      'game_id': 'game-zeta',
      'plugin_id': 'steam',
      'name': 'Zeta Hunters',
      'sorting_name': 'Zeta Hunters',
      'playtime_seconds': 5000,
    });

    // Seed achievements
    // 1. Alpha - Rare, high score, newest unlock
    await database.db.insert('achievements', {
      'game_id': 'game-alpha',
      'api_name': 'ACH_MASTER_SPY',
      'name': 'Master Spy',
      'description': 'Finish the game unseen.',
      'url_unlocked': 'spy.png',
      'date_unlocked_utc': '2026-11-20T12:00:00Z',
      'percent': 2.5,
      'gamer_score': 100.0,
      'is_hidden': 0,
    });

    // 2. Alpha - Common, low score, older unlock
    await database.db.insert('achievements', {
      'game_id': 'game-alpha',
      'api_name': 'ACH_FIRST_MISSION',
      'name': 'First Mission',
      'description': 'Complete orientation.',
      'url_unlocked': 'mission.png',
      'date_unlocked_utc': '2026-11-10T08:00:00Z',
      'percent': 88.0,
      'gamer_score': 10.0,
      'is_hidden': 0,
    });

    // 3. Zeta - Medium rarity, mid score, middle unlock
    await database.db.insert('achievements', {
      'game_id': 'game-zeta',
      'api_name': 'ACH_HUNTER_INITIATE',
      'name': 'Initiate Hunter',
      'description': 'Hunt first target.',
      'url_unlocked': 'hunter.png',
      'date_unlocked_utc': '2026-11-15T10:00:00Z',
      'percent': 35.0,
      'gamer_score': 25.0,
      'is_hidden': 0,
    });

    // 4. Locked achievement (must be excluded from global unlocked browser)
    await database.db.insert('achievements', {
      'game_id': 'game-zeta',
      'api_name': 'ACH_LOCKED_SECRETS',
      'name': 'Locked Secrets',
      'description': 'Never unlocked.',
      'url_unlocked': null,
      'date_unlocked_utc': null,
      'percent': 0.5,
      'gamer_score': 500.0,
      'is_hidden': 1,
    });
  });

  tearDownAll(() async {
    await database.close();
  });

  group('StatsDao - Global Achievements Queries (Ticket #25)', () {
    test('1. getGlobalAchievementsPaged returns only unlocked items and respects limit/offset', () async {
      final totalCount = await statsDao.getGlobalAchievementsCount();
      expect(totalCount, equals(3));

      final page1 = await statsDao.getGlobalAchievementsPaged(limit: 2, offset: 0);
      expect(page1.length, equals(2));

      final page2 = await statsDao.getGlobalAchievementsPaged(limit: 2, offset: 2);
      expect(page2.length, equals(1));
    });

    test('2. Supports dynamic sorting: newest, oldest, rarity, score, game title', () async {
      // Newest first
      final newest = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.unlockDateDesc);
      expect(newest.first.name, equals('Master Spy'));
      expect(newest.last.name, equals('First Mission'));

      // Oldest first
      final oldest = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.unlockDateAsc);
      expect(oldest.first.name, equals('First Mission'));
      expect(oldest.last.name, equals('Master Spy'));

      // Rarest first (lowest percent)
      final rarest = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.rarityAsc);
      expect(rarest.first.name, equals('Master Spy')); // 2.5%
      expect(rarest[1].name, equals('Initiate Hunter')); // 35.0%
      expect(rarest.last.name, equals('First Mission')); // 88.0%

      // Most common first (highest percent)
      final common = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.rarityDesc);
      expect(common.first.name, equals('First Mission')); // 88.0%

      // Score desc
      final highScore = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.scoreDesc);
      expect(highScore.first.name, equals('Master Spy')); // 100 pts
      expect(highScore.last.name, equals('First Mission')); // 10 pts

      // Game Title A-Z
      final byGame = await statsDao.getGlobalAchievementsPaged(sort: GlobalAchievementSort.gameTitleAsc);
      expect(byGame.first.gameName, equals('Alpha Protocol'));
      expect(byGame.last.gameName, equals('Zeta Hunters'));
    });

    test('3. Filters achievements by search query on achievement name and game title', () async {
      // Search by achievement name
      final searchAch = await statsDao.getGlobalAchievementsPaged(searchQuery: 'Hunter');
      expect(searchAch.length, equals(1));
      expect(searchAch.first.name, equals('Initiate Hunter'));

      // Search by game name
      final searchGame = await statsDao.getGlobalAchievementsPaged(searchQuery: 'Zeta');
      expect(searchGame.length, equals(1));
      expect(searchGame.first.name, equals('Initiate Hunter'));

      // Count with search query
      final count = await statsDao.getGlobalAchievementsCount(searchQuery: 'Alpha');
      expect(count, equals(2));
    });
  });

  group('GlobalAchievementsBrowser Widget Tests (Ticket #25)', () {
    testWidgets('1. Renders browser list with search input, sort dropdown, and metrics', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: GlobalAchievementsBrowser(statsDao: statsDao),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('3 unlocked'), findsOneWidget);
      expect(find.text('Master Spy'), findsOneWidget);
      expect(find.text('Initiate Hunter'), findsOneWidget);
      expect(find.text('First Mission'), findsOneWidget);

      // Verify badges
      expect(find.text('2.5%'), findsOneWidget);
      expect(find.text('⚡ 100 pts'), findsOneWidget);

      // Teardown invariant
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('2. Tapping achievement row opens AchievementDetailModal and allows navigating to game', (tester) async {
      String? tappedGameId;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: GlobalAchievementsBrowser(
                statsDao: statsDao,
                onGameTap: (id) => tappedGameId = id,
              ),
            ),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Tap Master Spy
      await tester.tap(find.text('Master Spy'));
      await tester.pumpAndSettle();

      // Modal is open
      expect(find.text('DESCRIPTION'), findsOneWidget);
      expect(find.text('Finish the game unseen.'), findsOneWidget);
      expect(find.text('View Game'), findsOneWidget);

      // Tap View Game
      await tester.tap(find.text('View Game'));
      await tester.pumpAndSettle();

      expect(tappedGameId, equals('game-alpha'));

      // Teardown invariant
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
