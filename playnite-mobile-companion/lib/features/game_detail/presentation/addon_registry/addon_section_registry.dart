import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'i_addon_widget.dart';
import 'sections/achievements_section.dart';
import 'sections/activity_section.dart';
import 'sections/dlc_section.dart';
import 'sections/fallback_addon_section.dart';
import 'sections/hltb_section.dart';
import 'sections/requirements_section.dart';
import 'sections/steam_reviews_section.dart';

/// Polymorphic registry for rendering dynamic addon cards in the Game Detail screen.
/// Guarantees graceful degradation: missing addons simply don't render; unknown addons
/// render via FallbackAddonSection; faulty addon code never crashes the detail view.
class AddonSectionRegistry {
  static final Map<String, IAddonSectionWidget> _registry = {};
  static bool _initialized = false;

  /// Registers an addon widget builder for a specific addon payload key.
  static void register(IAddonSectionWidget widget) {
    _registry[widget.addonKey] = widget;
  }

  /// Initializes the registry with default supported addons.
  static void initDefaults() {
    if (_initialized) return;
    _initialized = true;

    register(const AchievementsSection());
    register(const HltbSection());
    register(const ActivitySection());
    register(const DlcSection());
    register(const RequirementsSection());
    register(const SteamReviewsSection());
  }

  /// Clears custom registrations and resets defaults (useful for tests)
  static void reset() {
    _registry.clear();
    _initialized = false;
    initDefaults();
  }

  /// Builds a list of available widgets for the given game payload.
  static List<Widget> buildAvailableSections(
    BuildContext context,
    UnifiedGamePayload game,
  ) {
    initDefaults();
    final widgets = <Widget>[];

    // 1. Sort registered sections by their displayOrder
    final sortedSections = _registry.values.toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    for (final section in sortedSections) {
      if (game.addons.containsKey(section.addonKey)) {
        final data = game.addons[section.addonKey];
        if (data is Map<String, dynamic> && data.isNotEmpty) {
          try {
            final widget = section.buildSection(context, data, game);
            if (widget is! SizedBox) {
              widgets.add(widget);
            }
          } catch (e, stack) {
            // Graceful degradation: never crash screen on addon rendering failure
            debugPrint('AddonSectionRegistry: Error rendering section "${section.addonKey}": $e\n$stack');
          }
        }
      }
    }

    // 2. Discover unknown future addons in the game payload
    final unknownKeys = game.addons.keys
        .where((key) => !_registry.containsKey(key))
        .toList()
      ..sort();

    for (final key in unknownKeys) {
      final data = game.addons[key];
      if (data != null) {
        widgets.add(FallbackAddonSection(
          addonKey: key,
          data: data,
        ));
      }
    }

    return widgets;
  }
}
