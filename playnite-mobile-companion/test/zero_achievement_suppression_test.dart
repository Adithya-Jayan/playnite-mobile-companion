import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/addon_section_registry.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/achievements_section.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/fallback_addon_section.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
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
  });
}
