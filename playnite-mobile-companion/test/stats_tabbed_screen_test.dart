import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/stats_dashboard_screen.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/most_played_leaderboard.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/recent_activity_timeline.dart';
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

    // Seed dummy game
    await database.db.insert('games', {
      'id': 'test-game-1',
      'game_id': 'test-game-1',
      'plugin_id': 'steam',
      'name': 'Hollow Knight: Silksong',
      'sorting_name': 'Hollow Knight: Silksong',
      'playtime_seconds': 7200,
      'is_installed': 1,
      'favorite': 1,
      'hidden': 0,
      'is_duplicate': 0,
    });

    // Seed play sessions
    await database.db.insert('play_sessions', {
      'game_id': 'test-game-1',
      'date_session_utc': '2026-11-20T10:00:00Z',
      'elapsed_seconds': 3600,
    });

    // Seed achievements
    await database.db.insert('achievements', {
      'game_id': 'test-game-1',
      'api_name': 'ACH_01',
      'name': 'Silk and Song',
      'description': 'Master the needle',
      'url_unlocked': 'silk.jpg',
      'date_unlocked_utc': '2026-11-20T11:00:00Z',
      'percent': 12.5,
      'gamer_score': 50,
      'is_hidden': 0,
    });
  });

    tearDownAll(() async {
      await database.close();
    });

    test('0. Verify StatsDao calculateLibraryStats returns totalGames > 0', () async {
      final statsDao = StatsDao(database);
      final stats = await statsDao.calculateLibraryStats();
      expect(stats.totalGames, 1);
      expect(stats.totalPlaytimeSeconds, 7200);
      expect(stats.topPlayedGames.length, 1);
    });

  group('StatsDashboardScreen Tabbed Reorganization & Navigation Tests (Ticket #24)', () {
    testWidgets('1. Displays 3 tabs: Overview, Activity, and Achievements', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: StatsDashboardScreen(database: database),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);

      // In Overview tab by default:
      expect(find.text('Total Playtime'), findsOneWidget);

      // Teardown invariant from AGENTS.md
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('2. Switching to Activity tab renders leaderboard and sessions', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: StatsDashboardScreen(database: database),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Tap Activity tab
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('Most Played Games'), findsOneWidget);
      expect(find.text('Recent Activity'), findsOneWidget);

      // Teardown invariant from AGENTS.md
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('3. Tapping a game in MostPlayedLeaderboard invokes navigation to GameDetailScreen', (tester) async {
      String? tappedGameId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: MostPlayedLeaderboard(
              topGames: const [
                TopPlayedGameEntry(
                  id: 'test-game-1',
                  name: 'Hollow Knight: Silksong',
                  playtimeSeconds: 7200,
                  coverDriveFileId: null,
                ),
              ],
              onGameTap: (id) => tappedGameId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hollow Knight: Silksong'), findsOneWidget);
      await tester.tap(find.text('Hollow Knight: Silksong'));
      await tester.pumpAndSettle();

      expect(tappedGameId, 'test-game-1');

      // Teardown invariant
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('4. Tapping game in RecentActivityTimeline invokes navigation', (tester) async {
      String? tappedGameId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: RecentActivityTimeline(
              sessions: const [
                RecentSessionEntry(
                  gameId: 'test-game-1',
                  gameName: 'Hollow Knight: Silksong',
                  dateSessionUtc: '2026-11-20T10:00:00Z',
                  elapsedSeconds: 3600,
                  coverDriveFileId: null,
                ),
              ],
              onGameTap: (id) => tappedGameId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hollow Knight: Silksong'), findsOneWidget);
      await tester.tap(find.text('Hollow Knight: Silksong'));
      await tester.pumpAndSettle();

      expect(tappedGameId, 'test-game-1');

      // Teardown invariant
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
