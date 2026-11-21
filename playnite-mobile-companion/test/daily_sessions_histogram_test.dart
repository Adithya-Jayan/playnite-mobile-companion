import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/activity_section.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Create 15 distinct daily sessions
  final sessionsList = List.generate(15, (index) {
    final dayNum = (index + 1).toString().padLeft(2, '0');
    return {
      'id': index + 1,
      'date_session_utc': '2026-11-${dayNum}T14:00:00Z',
      'elapsed_seconds': 3600 * (index % 4 + 1), // 1h to 4h
      'action_name': 'Steam Session',
    };
  });

  final activityData = {
    'sessions': sessionsList,
  };

  const dummyGame = UnifiedGamePayload(
    id: 'game-1',
    gameId: '12345',
    pluginId: 'steam',
    name: 'Test RPG',
    sortingName: 'Test RPG',
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

  group('Ticket #28: Daily Sessions Histogram Tests', () {
    testWidgets('1. Renders horizontally scrollable bar histogram with range filters', (tester) async {
      const section = ActivitySection();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section.buildSection(context, activityData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and default segments
      expect(find.text('Tracked Sessions (15)'), findsOneWidget);
      expect(find.text('Daily Sessions'), findsOneWidget);
      expect(find.text('Cumulative Hours'), findsOneWidget);

      // Check range selector chips
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('All Time'), findsOneWidget);

      // Verify that SingleChildScrollView with horizontal scrollDirection exists inside the histogram
      final scrollableFinder = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(scrollableFinder, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('2. Range selector chips filter the number of bars displayed', (tester) async {
      const section = ActivitySection();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section.buildSection(context, activityData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap '7 Days' range chip
      await tester.tap(find.text('7 Days'));
      await tester.pumpAndSettle();

      // In 7 Days range, there should only be 7 date labels rendered in the histogram
      // Let's check date labels: 11/15, 11/14, 11/13, 11/12, 11/11, 11/10, 11/09
      expect(find.text('11/15'), findsOneWidget);
      expect(find.text('11/09'), findsOneWidget);
      expect(find.text('11/01'), findsNothing); // 11/01 is excluded from 7 Days

      // Tap 'All Time'
      await tester.tap(find.text('All Time'));
      await tester.pumpAndSettle();

      expect(find.text('11/01'), findsOneWidget);
      expect(find.text('11/15'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('3. Tapping a bar selects the day and displays formatted playtime badge', (tester) async {
      const section = ActivitySection();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section.buildSection(context, activityData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 11/15 bar
      expect(find.text('11/15'), findsOneWidget);
      await tester.tap(find.text('11/15'));
      await tester.pumpAndSettle();

      // Badge showing selected date and duration appears
      expect(find.textContaining('2026-11-15:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('4. Does not overflow on narrow screens (e.g. 360px device width)', (tester) async {
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        oldOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = oldOnError;
      });

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const section = ActivitySection();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => SingleChildScrollView(
                child: section.buildSection(context, activityData, dummyGame),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
