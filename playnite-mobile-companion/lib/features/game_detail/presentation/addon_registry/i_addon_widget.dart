import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

/// Abstract contract for polymorphic addon section rendering in the Game Detail screen.
abstract class IAddonSectionWidget {
  /// The payload key in `game.addons[addonKey]`
  String get addonKey;

  /// Display ordering priority (lower numbers appear first)
  int get displayOrder;

  /// Human-readable title of this section
  String get title;

  /// Builds the widget tree for this addon section.
  /// Guaranteed that `addonData` is non-null when called.
  Widget buildSection(
    BuildContext context,
    Map<String, dynamic> addonData,
    UnifiedGamePayload game,
  );
}
