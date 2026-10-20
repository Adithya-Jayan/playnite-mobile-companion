import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/addon_section_registry.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/i_addon_widget.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/fallback_addon_section.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

class _FaultySection implements IAddonSectionWidget {
  @override
  String get addonKey => 'faulty_addon';

  @override
  int get displayOrder => 99;

  @override
  String get title => 'Faulty Addon';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    throw Exception('Simulated fatal render error');
  }
}

void main() {
  setUp(() {
    AddonSectionRegistry.reset();
  });

  group('AddonSectionRegistry & Graceful Degradation Tests', () {
    testWidgets('Addon Removal: Game without HLTB does not render HLTB section', (tester) async {
      final gameWithoutHltb = UnifiedGamePayload(
        id: 'game-1',
        gameId: 'app-1',
        pluginId: 'p1',
        name: 'Game Without HLTB',
        sortingName: 'Game Without HLTB',
        addons: {
          'success_story': {
            'total': 10,
            'unlocked': 5,
            'achievements': [],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithoutHltb);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Achievements section should be present
      expect(find.text('Achievements (5 / 10)'), findsOneWidget);
      // HLTB section should NOT be present
      expect(find.text('HowLongToBeat'), findsNothing);
    });

    testWidgets('Future / Unknown Addon: Renders gracefully via FallbackAddonSection', (tester) async {
      final gameWithFutureAddon = UnifiedGamePayload(
        id: 'game-2',
        gameId: 'app-2',
        pluginId: 'p1',
        name: 'Future Game',
        sortingName: 'Future Game',
        addons: {
          'community_patch_manager': {
            'installed_patches': ['v1.0.4-hotfix', '4k-upscale-textures'],
            'enabled': true,
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameWithFutureAddon);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Fallback section exists
      expect(find.byType(FallbackAddonSection), findsOneWidget);
      expect(find.text('Community Patch Manager'), findsOneWidget);
    });

    testWidgets('Fault Tolerance: Exception inside addon buildSection does not crash screen', (tester) async {
      AddonSectionRegistry.register(_FaultySection());

      final game = UnifiedGamePayload(
        id: 'game-3',
        gameId: 'app-3',
        pluginId: 'p1',
        name: 'Resilient Game',
        sortingName: 'Resilient Game',
        addons: {
          'faulty_addon': {'broken_data': 123},
          'success_story': {'total': 2, 'unlocked': 1, 'achievements': []},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, game);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // SuccessStory rendered cleanly despite faulty addon
      expect(find.text('Achievements (1 / 2)'), findsOneWidget);
      expect(find.text('Faulty Addon'), findsNothing);
    });

    testWidgets('Absent Addons & DuplicateHider: Renders zero addon sections and default single-game state without error', (tester) async {
      // JSON with absent addons, null duplicate fields, and absent other_copies
      final rawJson = {
        'schema_version': '1.0.0',
        'id': 'vanilla-game-1',
        'game_id': 'app-vanilla',
        'plugin_id': 'p1',
        'name': 'Vanilla Game',
        'sorting_name': 'Vanilla Game',
        'playtime_seconds': 3600,
        'play_count': 1,
        'is_installed': true,
        'hidden': false,
        'favorite': false,
        'is_duplicate': null,
        'duplicate_group_id': null,
        // other_copies omitted
        // addons omitted
      };

      final game = UnifiedGamePayload.fromJson(rawJson);
      expect(game.isDuplicate, isFalse);
      expect(game.duplicateGroupId, isNull);
      expect(game.otherCopies, isEmpty);
      expect(game.addons, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, game);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Verify zero addon sections generated and zero crashes
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
