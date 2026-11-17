import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/widgets/collapsible_stats_card.dart';

void main() {
  group('CollapsibleStatsCard Tests', () {
    testWidgets('1. Expands and collapses on header tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: CollapsibleStatsCard(
                title: 'Collapsible Section',
                icon: Icons.star,
                badge: '5 items',
                child: Text('Inner Content Visible'),
              ),
            ),
          ),
        ),
      );

      // Initially expanded
      expect(find.text('Collapsible Section'), findsOneWidget);
      expect(find.text('5 items'), findsOneWidget);
      expect(find.text('Inner Content Visible'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.text('Collapsible Section'));
      await tester.pumpAndSettle();

      // Content collapsed
      expect(find.text('Inner Content Visible'), findsNothing);

      // Tap header again to expand
      await tester.tap(find.text('Collapsible Section'));
      await tester.pumpAndSettle();

      expect(find.text('Inner Content Visible'), findsOneWidget);
    });

    testWidgets('2. Controlled expansion responds to external isExpanded', (tester) async {
      bool isExpanded = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => isExpanded = !isExpanded),
                    child: const Text('Toggle Externally'),
                  ),
                  CollapsibleStatsCard(
                    title: 'Controlled Card',
                    icon: Icons.pie_chart,
                    isExpanded: isExpanded,
                    onToggle: (v) => setState(() => isExpanded = v),
                    child: const Text('Controlled Content'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Initially collapsed
      expect(find.text('Controlled Content'), findsNothing);

      // External toggle to expand
      await tester.tap(find.text('Toggle Externally'));
      await tester.pumpAndSettle();
      expect(find.text('Controlled Content'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.text('Controlled Card'));
      await tester.pumpAndSettle();
      expect(find.text('Controlled Content'), findsNothing);
    });
  });
}
