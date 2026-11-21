import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/achievements_section.dart';
import 'package:playnite_mobile_companion/features/library/domain/library_preferences_service.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dummyGame = UnifiedGamePayload(
    id: 'game-1',
    gameId: '12345',
    pluginId: 'steam',
    name: 'Test Game',
    sortingName: 'Test Game',
    media: MediaPayload(),
    addons: {},
    platforms: [],
    genres: [],
    categories: [],
    tags: [],
    developers: [],
    publishers: [],
    features: [],
    series: [],
    links: [],
    otherCopies: [],
  );

  final dummyAddonData = {
    'has_achievements': true,
    'total_count': 3,
    'unlocked_count': 2,
    'achievements': [
      {
        'name': 'Bravo',
        'description': 'Desc B',
        'unlocked': true,
        'percent': 10.0,
        'date_unlocked': '2026-11-20T10:00:00Z',
      },
      {
        'name': 'Alpha',
        'description': 'Desc A',
        'unlocked': true,
        'percent': 50.0,
        'date_unlocked': '2026-11-19T10:00:00Z',
      },
      {
        'name': 'Charlie',
        'description': 'Desc C',
        'unlocked': false,
        'percent': 5.0,
      },
    ],
  };

  group('Ticket #27: Achievement Sort Order Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. LibraryPreferencesService stores and retrieves achievement sort option', () async {
      final prefsService = LibraryPreferencesService();

      expect(await prefsService.loadAchievementSort(), isNull);

      await prefsService.saveAchievementSort(AchievementSort.rarity.name);
      expect(await prefsService.loadAchievementSort(), equals('rarity'));

      await prefsService.saveAchievementSort(AchievementSort.unlockDate.name);
      expect(await prefsService.loadAchievementSort(), equals('unlockDate'));
    });

    testWidgets('2. AchievementsSection loads persisted sort order on mount', (tester) async {
      SharedPreferences.setMockInitialValues({
        'pref_achievement_sort': 'rarity',
      });

      const section = AchievementsSection();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section.buildSection(context, dummyAddonData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that the sort dropdown displays "Rarity"
      expect(find.text('Sort: Rarity'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('3. Changing sort order persists to preferences and re-mounting restores saved sort', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefsService = LibraryPreferencesService();

      final section1 = AchievementsSection(preferencesService: prefsService);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section1.buildSection(context, dummyAddonData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Defaults to A-Z
      expect(find.text('Sort: A-Z'), findsOneWidget);

      // Open dropdown and select 'Unlock Date'
      await tester.tap(find.text('A-Z'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unlock Date').last);
      await tester.pumpAndSettle();

      expect(find.text('Sort: Unlock Date'), findsOneWidget);

      // Verify preference was saved
      final savedSort = await prefsService.loadAchievementSort();
      expect(savedSort, equals('unlockDate'));

      // Unmount
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Re-mount new instance
      final section2 = AchievementsSection(preferencesService: prefsService);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section2.buildSection(context, dummyAddonData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should restore 'Unlock Date'
      expect(find.text('Sort: Unlock Date'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
