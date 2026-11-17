import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/recent_achievements_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Recent Achievements Stats - DAO Tests', () {
    late AppDatabase database;
    late StatsDao statsDao;

    setUp(() async {
      database = AppDatabase.instance;
      await database.init(inMemory: true);
      await database.reset();
      statsDao = StatsDao(database);

      // Seed game
      await database.db.insert('games', {
        'id': 'game-silksong',
        'game_id': 'game-silksong',
        'plugin_id': 'steam',
        'name': 'Hollow Knight: Silksong',
        'sorting_name': 'Hollow Knight: Silksong',
        'playtime_seconds': 36000,
        'cover_drive_file_id': 'cover_silksong_drive_id',
      });

      // Seed achievements with unlock dates
      await database.db.insert('achievements', {
        'game_id': 'game-silksong',
        'api_name': 'ACH_BONDED',
        'name': 'Bonded',
        'description': 'Forge an unbreakable connection.',
        'url_unlocked': 'icon_bonded_unlocked',
        'date_unlocked_utc': '2026-11-16T14:30:00.000Z',
        'percent': 12.5,
        'gamer_score': 30.0,
      });

      await database.db.insert('achievements', {
        'game_id': 'game-silksong',
        'api_name': 'ACH_FIRST_STEPS',
        'name': 'First Steps in Pharloom',
        'description': 'Arrive in the mossy outskirts.',
        'url_unlocked': 'icon_first_steps_unlocked',
        'date_unlocked_utc': '2026-11-10T10:00:00.000Z',
        'percent': 85.0,
        'gamer_score': 10.0,
      });

      // Locked achievement (date_unlocked_utc null)
      await database.db.insert('achievements', {
        'game_id': 'game-silksong',
        'api_name': 'ACH_SILK_SOUL',
        'name': 'Silk Soul Master',
        'description': 'Complete Silk Soul mode.',
        'url_unlocked': 'icon_silk_soul',
        'date_unlocked_utc': null,
      });
    });

    tearDownAll(() async {
      await database.close();
    });

    test('1. StatsDao queries recent unlocked achievements ordered by date_unlocked_utc desc', () async {
      final stats = await statsDao.calculateLibraryStats();
      expect(stats.recentAchievements.length, equals(2));
      expect(stats.recentAchievements.first.name, equals('Bonded'));
      expect(stats.recentAchievements.first.gameName, equals('Hollow Knight: Silksong'));
      expect(stats.recentAchievements.first.gamerScore, equals(30.0));
      expect(stats.recentAchievements[1].name, equals('First Steps in Pharloom'));
    });
  });

  group('Recent Achievements Stats - Widget Tests', () {
    testWidgets('2. RecentAchievementsTimeline renders achievements and details', (tester) async {
      final dummyAchievements = [
        const RecentAchievementEntry(
          id: 1,
          gameId: 'game-silksong',
          gameName: 'Hollow Knight: Silksong',
          apiName: 'ACH_BONDED',
          name: 'Bonded',
          description: 'Forge an unbreakable connection.',
          dateUnlockedUtc: '2026-11-16T14:30:00.000Z',
          gamerScore: 30.0,
        ),
        const RecentAchievementEntry(
          id: 2,
          gameId: 'game-silksong',
          gameName: 'Hollow Knight: Silksong',
          apiName: 'ACH_FIRST_STEPS',
          name: 'First Steps in Pharloom',
          dateUnlockedUtc: '2026-11-10T10:00:00.000Z',
          gamerScore: 10.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentAchievementsTimeline(achievements: dummyAchievements),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Recent Achievements'), findsOneWidget);
      expect(find.text('2 unlocked'), findsOneWidget);
      expect(find.text('Bonded'), findsOneWidget);
      expect(find.text('Hollow Knight: Silksong'), findsNWidgets(2));
      expect(find.text('+30G'), findsOneWidget);
      expect(find.text('+10G'), findsOneWidget);
    });

    testWidgets('3. RecentAchievementsTimeline renders empty shrink when list is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentAchievementsTimeline(achievements: []),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Recent Achievements'), findsNothing);
    });
  });
}
