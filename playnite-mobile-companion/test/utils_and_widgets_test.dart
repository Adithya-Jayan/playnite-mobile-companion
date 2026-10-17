import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/completion_pie_chart.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/most_played_leaderboard.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/platform_breakdown_bar.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/playtime_summary_card.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/recent_activity_timeline.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  group('Utility Unit Tests', () {
    test('DurationFormatter formats seconds correctly', () {
      expect(DurationFormatter.formatSecondsToHoursMinutes(0), equals('0m'));
      expect(DurationFormatter.formatSecondsToHoursMinutes(125), equals('2m'));
      expect(DurationFormatter.formatSecondsToHoursMinutes(3600), equals('1h'));
      expect(DurationFormatter.formatSecondsToHoursMinutes(3660), equals('1h 1m'));
      expect(DurationFormatter.formatSecondsToHoursMinutes(94500), equals('26h 15m'));
      expect(DurationFormatter.formatSecondsToHoursMinutes(93612), equals('26h'));

      expect(DurationFormatter.formatSecondsToDecimalHours(0), equals('0.0h'));
      expect(DurationFormatter.formatSecondsToDecimalHours(93600), equals('26.0h'));
      expect(DurationFormatter.formatSecondsToDecimalHours(3600), equals('1.0h'));

      expect(DurationFormatter.formatTotalPlaytimeSummary(18450000), contains('5,125 Hours'));
      expect(DurationFormatter.formatBytes(2145728), equals('2.0 MB'));
      expect(DurationFormatter.formatBytes(1024), equals('1.0 KB'));
    });

    test('MediaUrlResolver generates correct Google Drive stream URLs and headers', () {
      MediaUrlResolver.setAuthToken('test-bearer-token');
      expect(MediaUrlResolver.authToken, equals('test-bearer-token'));

      final streamUrl = MediaUrlResolver.getDriveMediaStreamUrl('drive-file-abc-123');
      expect(streamUrl, equals('https://www.googleapis.com/drive/v3/files/drive-file-abc-123?alt=media'));

      final thumbUrl = MediaUrlResolver.getDriveThumbnailUrl('drive-file-abc-123', width: 500);
      expect(thumbUrl, equals('https://drive.google.com/thumbnail?id=drive-file-abc-123&sz=w500'));

      final headers = MediaUrlResolver.getAuthHeaders();
      expect(headers['Authorization'], equals('Bearer test-bearer-token'));

      // Direct URL pass-through
      expect(
        MediaUrlResolver.getDriveMediaStreamUrl('https://example.com/trailer.mp4'),
        equals('https://example.com/trailer.mp4'),
      );
    });
  });

  group('UI Screens & Widgets Tests', () {
    testWidgets('GameDetailScreen renders title, playtime, external links and addon sections', (tester) async {
      final game = UnifiedGamePayload(
        id: 'cyberpunk-id',
        gameId: '1091500',
        pluginId: 'steam-plugin',
        name: 'Cyberpunk 2077',
        sortingName: 'Cyberpunk 2077',
        description: '<p>A futuristic open world RPG.</p>',
        playtimeSeconds: 756000,
        playCount: 48,
        isInstalled: true,
        favorite: true,
        userScore: 92,
        releaseDate: '2020-12-10',
        source: const NamedItem(id: 'steam', name: 'Steam'),
        completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
        platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
        genres: const [NamedItem(id: 'rpg', name: 'RPG')],
        developers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        publishers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        links: const [
          LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/1091500/'),
        ],
        media: const MediaPayload(
          microtrailerDriveFileId: 'mock-trailer',
          backgroundDriveFileId: 'mock-bg',
          logoDriveFileId: 'mock-logo',
        ),
        addons: {
          'how_long_to_beat': {
            'main_story_seconds': 93600,
            'main_extra_seconds': 216000,
            'completionist_seconds': 374400,
          },
          'steam_reviews_viewer': {
            'positive_percent': 91,
            'total_reviews': 710000,
            'review_score_desc': 'Very Positive',
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GameDetailScreen(game: game),
        ),
      );
      await tester.pump();

      // Title & developer
      expect(find.text('Cyberpunk 2077'), findsOneWidget);
      expect(find.text('CD PROJEKT RED'), findsOneWidget);

      // Playtime
      expect(find.text('210h'), findsOneWidget);

      // External link chip
      expect(find.text('Steam Store'), findsOneWidget);

      // Addons
      expect(find.text('HowLongToBeat'), findsOneWidget);
      expect(find.text('Very Positive'), findsOneWidget);
    });

    testWidgets('Stats dashboard widgets render playtime, charts, leaderboard and activity', (tester) async {
      const stats = LibraryStats(
        totalGames: 42,
        totalPlaytimeSeconds: 987654,
        installedCount: 15,
        favoritesCount: 8,
        playtimeBySource: {'Steam': 600000, 'GOG': 387654},
        playtimeByPlatform: {'PC (Windows)': 987654},
        completionBreakdown: {'Completed': 12, 'Playing': 5, 'Not Played': 25},
        topPlayedGames: [
          TopPlayedGameEntry(id: 'g1', name: 'The Witcher 3: Wild Hunt', playtimeSeconds: 500000),
          TopPlayedGameEntry(id: 'g2', name: 'Cyberpunk 2077', playtimeSeconds: 300000),
        ],
        recentSessions: [
          RecentSessionEntry(
            gameId: 'g1',
            gameName: 'The Witcher 3: Wild Hunt',
            dateSessionUtc: '2026-10-14T20:30:00Z',
            elapsedSeconds: 7200,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const PlaytimeSummaryCard(stats: stats),
                  CompletionPieChart(completionBreakdown: stats.completionBreakdown),
                  PlatformBreakdownBar(
                    title: 'Playtime by Storefront',
                    icon: Icons.storefront,
                    distribution: stats.playtimeBySource,
                  ),
                  MostPlayedLeaderboard(topGames: stats.topPlayedGames),
                  RecentActivityTimeline(sessions: stats.recentSessions),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Playtime Summary Card
      expect(find.text('Total Playtime'), findsOneWidget);
      expect(find.text('42'), findsOneWidget); // Total games count
      expect(find.text('15'), findsOneWidget); // Installed count
      expect(find.text('8'), findsOneWidget); // Favorites count

      // Completion Chart
      expect(find.text('Completion Status'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.textContaining('(12)'), findsOneWidget);

      // Platform Breakdown Bar
      expect(find.text('Playtime by Storefront'), findsOneWidget);
      expect(find.text('Steam'), findsOneWidget);
      expect(find.text('GOG'), findsOneWidget);

      // Most Played Leaderboard
      expect(find.text('Most Played Games'), findsOneWidget);
      expect(find.text('The Witcher 3: Wild Hunt'), findsWidgets);
      expect(find.text('Cyberpunk 2077'), findsOneWidget);

      // Recent Activity Timeline
      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
    });
  });
}
