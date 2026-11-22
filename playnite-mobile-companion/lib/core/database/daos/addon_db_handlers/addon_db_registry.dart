import 'achievements_db_handler.dart';
import 'dlc_db_handler.dart';
import 'hltb_db_handler.dart';
import 'i_addon_db_handler.dart';
import 'sessions_db_handler.dart';

/// Registry holding active database handlers for modular addon table ingestion,
/// deletion, and on-demand relational retrieval.
class AddonDbRegistry {
  static final List<IAddonDbHandler> _handlers = [];
  static bool _initialized = false;

  /// Returns unmodifiable list of registered addon database handlers.
  static List<IAddonDbHandler> get handlers {
    initDefaults();
    return List.unmodifiable(_handlers);
  }

  /// Set of all payload keys supported by relational database handlers.
  static Set<String> get allSupportedKeys {
    initDefaults();
    final keys = <String>{};
    for (final h in _handlers) {
      keys.add(h.addonKey);
      keys.addAll(h.handledKeys);
    }
    return keys;
  }

  /// Locates the handler responsible for a given payload key.
  static IAddonDbHandler? getHandler(String key) {
    initDefaults();
    for (final h in _handlers) {
      if (h.addonKey == key || h.handledKeys.contains(key)) {
        return h;
      }
    }
    return null;
  }

  /// Registers an addon DB handler. Overrides any existing handler with the same addonKey.
  static void register(IAddonDbHandler handler) {
    _handlers.removeWhere((h) => h.addonKey == handler.addonKey);
    _handlers.add(handler);
  }

  /// Initializes default handlers (Achievements, Sessions, HowLongToBeat, CheckDlc).
  static void initDefaults() {
    if (_initialized) return;
    _initialized = true;
    _handlers.add(AchievementsDbHandler());
    _handlers.add(SessionsDbHandler());
    _handlers.add(HltbDbHandler());
    _handlers.add(DlcDbHandler());
  }

  /// Resets handlers back to defaults (useful for unit test isolation).
  static void reset() {
    _handlers.clear();
    _initialized = false;
    initDefaults();
  }
}
