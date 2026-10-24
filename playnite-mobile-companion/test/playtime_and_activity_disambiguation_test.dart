import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/activity_section.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/widgets/play_time_card.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/game_card_grid.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/game_details_tile.dart';
import 'package:playnite_mobile_companion/features/library/presentation/widgets/game_list_tile.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Authoritative Playtime & Session Disambiguation Tests', () {
    const activityDataSample = {
      'sessions': [
        {
          'id': 1,
          'date_session_utc': '2026-10-20T14:30:00Z',
          'elapsed_seconds': 3600, // 1h 0m
          'action_name': 'Steam Launch',
        },
        {
          'id': 2,
          'date_session_utc': '2026-10-21T18:00:00Z',
          'elapsed_seconds': 5400, // 1h 30m
          'action_name': 'Manual Session',
        },
      ],
    };

    // Total sessions = 2, total elapsed = 9000 seconds (2h 30m)
    // Game core playtime is intentionally different: 361,800 seconds (100h 30m)
    const authoritativePlaytimeSeconds = 361800;

    const testGame = UnifiedGamePayload(
      id: 'witcher-3-id',
      gameId: 'witcher-3-gameid',
      pluginId: 'gog_plugin',
      name: 'The Witcher 3: Wild Hunt',
      sortingName: 'Witcher 3: Wild Hunt',
      playtimeSeconds: authoritativePlaytimeSeconds,
      playCount: 42,
      lastActivityUtc: '2026-10-21T19:30:00Z',
      userScore: 95,
      source: NamedItem(id: 'gog', name: 'GOG'),
      media: MediaPayload(
        coverDriveFileId: 'cover_123',
      ),
      addons: {
        'game_activity': activityDataSample,
      },
    );

    test('ActivitySection metadata returns "Tracked Sessions" as title', () {
      const section = ActivitySection();
      expect(section.addonKey, equals('game_activity'));
      expect(section.title, equals('Tracked Sessions'));
    });

    testWidgets('PlayTimeCard displays authoritative Playnite playtime and not session total', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlayTimeCard(game: testGame),
          ),
        ),
      );

      // Must display 100h 30m (authoritative Playnite core playtime)
      expect(find.text('100h 30m'), findsOneWidget);
      expect(find.text('Playtime'), findsOneWidget);
      expect(find.text('42 times'), findsOneWidget);

      // Must NOT display session sum
      expect(find.text('2h 30m'), findsNothing);
    });

    testWidgets('GameCardGrid displays authoritative Playnite playtime', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 300,
              child: GameCardGrid(game: testGame),
            ),
          ),
        ),
      );

      expect(find.text('100h 30m'), findsOneWidget);
      expect(find.text('2h 30m'), findsNothing);
    });

    testWidgets('GameListTile displays authoritative Playnite playtime', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameListTile(game: testGame),
          ),
        ),
      );

      // Subtitle contains: GOG • 100h 30m
      expect(find.textContaining('100h 30m'), findsOneWidget);
      expect(find.textContaining('2h 30m'), findsNothing);
    });

    testWidgets('GameDetailsTile displays authoritative Playnite playtime badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GameDetailsTile(game: testGame),
          ),
        ),
      );

      expect(find.text('100h 30m'), findsOneWidget);
      expect(find.text('2h 30m'), findsNothing);
    });

    testWidgets('ActivitySection disambiguates sessions from total playtime in header', (tester) async {
      const section = ActivitySection();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Builder(
                  builder: (context) => section.buildSection(
                    context,
                    activityDataSample,
                    testGame,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Header must explicitly state Tracked Sessions (count)
      expect(find.text('Tracked Sessions (2)'), findsOneWidget);

      // Total session duration must be disambiguated with Logged: and Session Total subtitle
      expect(find.text('Logged: 2h 30m'), findsOneWidget);
      expect(find.text('Session Total'), findsOneWidget);

      // Header should NEVER confuse the user with just an ambiguous total duration
      expect(find.text('Play Sessions (2)'), findsNothing);
    });

    testWidgets('Manual Playtime Edit in Playnite propagates cleanly to all cards', (tester) async {
      // User manually edited playtime in Playnite from 100h 30m (361,800s) to 150h 45m (542,700s)
      final editedGame = testGame.copyWith(
        playtimeSeconds: 542700,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  PlayTimeCard(game: editedGame),
                  SizedBox(
                    width: 200,
                    height: 300,
                    child: GameCardGrid(game: editedGame),
                  ),
                  GameListTile(game: editedGame),
                  GameDetailsTile(game: editedGame),
                ],
              ),
            ),
          ),
        ),
      );

      // All components must display the newly edited authoritative playtime 150h 45m
      expect(find.text('150h 45m'), findsNWidgets(3)); // PlayTimeCard, GameCardGrid, GameDetailsTile
      expect(find.textContaining('150h 45m'), findsNWidgets(4)); // + GameListTile subtitle
    });

    test('StatsDao calculates totalPlaytimeSeconds strictly from Playnite games table', () async {
      final appDatabase = AppDatabase.instance;
      await appDatabase.init(inMemory: true);
      await appDatabase.reset();
      final db = appDatabase.db;

      // Seed game with manual playtime of 72,000 seconds (20 hours)
      await db.insert('games', {
        'id': 'g1',
        'game_id': 'app-1',
        'plugin_id': 'p1',
        'name': 'Authoritative Witcher',
        'sorting_name': 'Authoritative Witcher',
        'playtime_seconds': 72000,
        'play_count': 5,
        'is_installed': 1,
        'favorite': 1,
        'source_name': 'Steam',
        'platforms_json': '[{"id":"pc","name":"PC"}]',
        'completion_status_name': 'Completed',
        'added_utc': '2026-01-01T00:00:00Z',
      });

      // Insert play sessions that only total 3,600 seconds (1 hour)
      await db.insert('play_sessions', {
        'game_id': 'g1',
        'date_session_utc': '2026-01-02T10:00:00Z',
        'elapsed_seconds': 3600,
        'action_name': 'Play session',
      });

      final statsDao = StatsDao(appDatabase);
      final stats = await statsDao.calculateLibraryStats();

      // Authoritative Playnite playtime must be 72,000 seconds (20h), NOT 3,600 seconds
      expect(stats.totalPlaytimeSeconds, equals(72000));
      expect(stats.playtimeBySource['Steam'], equals(72000));
      expect(stats.playtimeByPlatform['PC'], equals(72000));
      expect(stats.topPlayedGames.first.playtimeSeconds, equals(72000));

      // Recent sessions accurately track the individual logged activity
      expect(stats.recentSessions.length, equals(1));
      expect(stats.recentSessions.first.elapsedSeconds, equals(3600));

      await appDatabase.close();
    });
  });
}
