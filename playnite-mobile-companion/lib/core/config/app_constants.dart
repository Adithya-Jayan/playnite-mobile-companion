/// Global application constants.
class AppConstants {
  static const String appName = 'Playnite Mobile Companion';
  static const String appVersion = '1.0.0';

  // Remote Sync Endpoints and Names
  static const String defaultSyncFolder = 'PlayniteSync';
  static const String syncIndexFileName = 'sync_index.json';
  static const String manifestFileName = 'manifest.json';

  // Categories (Canonical parity with desktop exporter enum)
  static const String categoryManifest = 'manifest';
  static const String categoryGameMetadata = 'game_metadata';
  static const String categoryCover = 'cover';
  static const String categoryBackground = 'background';
  static const String categoryLogo = 'logo';
  static const String categoryMicrotrailer = 'microtrailer';
  static const String categoryTrailer = 'trailer';
  static const String categoryIcon = 'icon';

  // Legacy Category Constants (pre-1.0 format)
  static const String legacyCategoryCover = 'media_cover';
  static const String legacyCategoryBackground = 'media_background';
  static const String legacyCategoryLogo = 'media_logo';
  static const String legacyCategoryMicrotrailer = 'media_microtrailer';
  static const String legacyCategoryTrailer = 'media_trailer';

  /// Normalizes any category string (including legacy 'media_' prefix) to the canonical desktop enum string.
  static String normalizeCategory(String? category) {
    if (category == null || category.isEmpty) return '';
    final cat = category.toLowerCase().trim();
    switch (cat) {
      case legacyCategoryCover:
      case categoryCover:
        return categoryCover;
      case legacyCategoryBackground:
      case categoryBackground:
        return categoryBackground;
      case legacyCategoryLogo:
      case categoryLogo:
        return categoryLogo;
      case legacyCategoryMicrotrailer:
      case categoryMicrotrailer:
        return categoryMicrotrailer;
      case legacyCategoryTrailer:
      case categoryTrailer:
        return categoryTrailer;
      case categoryIcon:
        return categoryIcon;
      case categoryManifest:
        return categoryManifest;
      case categoryGameMetadata:
        return categoryGameMetadata;
      default:
        if (cat.startsWith('media_')) {
          return cat.substring(6);
        }
        return cat;
    }
  }

  /// Checks if a category corresponds to a video asset (microtrailer or trailer).
  static bool isVideoCategory(String? category) {
    final norm = normalizeCategory(category);
    return norm == categoryMicrotrailer || norm == categoryTrailer;
  }

  /// Checks if a category corresponds to any media asset (cover, background, icon, logo, trailer, etc.).
  static bool isMediaCategory(String? category) {
    final norm = normalizeCategory(category);
    return norm == categoryCover ||
        norm == categoryBackground ||
        norm == categoryLogo ||
        norm == categoryMicrotrailer ||
        norm == categoryTrailer ||
        norm == categoryIcon ||
        norm == 'media' ||
        norm == 'achievement_icon';
  }

  // Known Addon Keys
  static const String addonSuccessStory = 'success_story';
  static const String addonHowLongToBeat = 'how_long_to_beat';
  static const String addonGameActivity = 'game_activity';
  static const String addonCheckDlc = 'check_dlc';
  static const String addonSystemChecker = 'system_checker';
  static const String addonSteamReviews = 'steam_reviews_viewer';
  static const String addonSteamScreenshots = 'steam_screenshots';
  static const String addonExtraMetadata = 'extra_metadata_loader';
  static const String addonPlayerActivities = 'player_activities';

  // Database
  static const String databaseFileName = 'playnite_companion.db';
  static const int databaseVersion = 3;
}
