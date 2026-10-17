/// Global application constants.
class AppConstants {
  static const String appName = 'Playnite Companion';
  static const String appVersion = '1.0.0';

  // Remote Sync Endpoints and Names
  static const String defaultSyncFolder = 'PlayniteSync';
  static const String syncIndexFileName = 'sync_index.json';
  static const String manifestFileName = 'manifest.json';

  // Categories
  static const String categoryManifest = 'manifest';
  static const String categoryGameMetadata = 'game_metadata';
  static const String categoryCover = 'media_cover';
  static const String categoryBackground = 'media_background';
  static const String categoryLogo = 'media_logo';
  static const String categoryMicrotrailer = 'media_microtrailer';
  static const String categoryTrailer = 'media_trailer';

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
  static const int databaseVersion = 1;
}
