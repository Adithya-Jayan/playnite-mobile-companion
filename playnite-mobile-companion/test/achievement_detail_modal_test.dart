import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/ui/achievement_detail_modal.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/recent_achievements_timeline.dart';

void main() {
  group('AchievementDetailModal & Tap Interaction Tests', () {
    testWidgets('1. Renders achievement detail modal with full metadata', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  AchievementDetailModal.show(
                    context,
                    name: 'True Hunter',
                    description: 'Acquire the Hunter’s Mark and complete all journal entries.',
                    gameName: 'Hollow Knight: Silksong',
                    iconUrl: 'https://example.com/icon.jpg',
                    isUnlocked: true,
                    dateUnlockedUtc: '2026-11-15T14:54:20.000Z',
                    percent: 0.7,
                    gamerScore: 70.0,
                    category: 'Journal',
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify modal contents
      expect(find.text('True Hunter'), findsOneWidget);
      expect(find.text('Hollow Knight: Silksong'), findsOneWidget);
      expect(find.text('Acquire the Hunter’s Mark and complete all journal entries.'), findsOneWidget);
      expect(find.textContaining('0.7% (Ultra Rare)'), findsOneWidget);
      expect(find.text('70 pts'), findsOneWidget);
      expect(find.text('Journal'), findsOneWidget);
      expect(find.textContaining('Unlocked:'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Close button
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('True Hunter'), findsNothing);
    });

    testWidgets('2. Tapping achievement in RecentAchievementsTimeline opens detail modal', (tester) async {
      final sampleAchievements = [
        RecentAchievementEntry(
          id: 1,
          gameId: 'silksong-uuid',
          gameName: 'Hollow Knight: Silksong',
          coverDriveFileId: null,
          apiName: 'FIRST_TOOL',
          name: 'Equipped',
          description: 'Equip your first tool into a crest slot.',
          urlUnlocked: 'https://example.com/tool.jpg',
          dateUnlockedUtc: '2026-11-15T14:00:00.000Z',
          percent: 85.0,
          gamerScore: 10.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecentAchievementsTimeline(achievements: sampleAchievements),
            ),
          ),
        ),
      );

      expect(find.text('Equipped'), findsOneWidget);

      // Tap on the achievement item
      await tester.tap(find.text('Equipped'));
      await tester.pumpAndSettle();

      // Verify modal appeared
      expect(find.text('Equipped'), findsNWidgets(2)); // in timeline and in modal header
      expect(find.text('Equip your first tool into a crest slot.'), findsNWidgets(2));
      expect(find.text('10 pts'), findsOneWidget);
      expect(find.textContaining('85.0% (Common)'), findsOneWidget);
    });
  });
}
