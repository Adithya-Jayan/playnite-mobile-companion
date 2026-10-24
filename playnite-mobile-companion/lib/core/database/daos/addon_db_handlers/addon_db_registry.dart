import 'achievements_db_handler.dart';
import 'i_addon_db_handler.dart';
import 'sessions_db_handler.dart';

/// Registry holding active database handlers for modular addon table ingestion.
class AddonDbRegistry {
  static final List<IAddonDbHandler> _handlers = [];
  static bool _initialized = false;

  /// Returns unmodifiable list of registered addon database handlers.
  static List<IAddonDbHandler> get handlers {
    initDefaults();
    return List.unmodifiable(_handlers);
  }

  /// Registers an addon DB handler. Overrides any existing handler with the same addonKey.
  static void register(IAddonDbHandler handler) {
    _handlers.removeWhere((h) => h.addonKey == handler.addonKey);
    _handlers.add(handler);
  }

  /// Initializes default handlers (AchievementsDbHandler and SessionsDbHandler).
  static void initDefaults() {
    if (_initialized) return;
    _initialized = true;
    _handlers.add(AchievementsDbHandler());
    _handlers.add(SessionsDbHandler());
  }

  /// Resets handlers back to defaults (useful for unit test isolation).
  static void reset() {
    _handlers.clear();
    _initialized = false;
    initDefaults();
  }
}
