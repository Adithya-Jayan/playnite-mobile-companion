import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

/// Supported sources for rating scores and filtering.
enum RatingScoreSource {
  community, // Public / Community Score (Steam/IGDB) - DEFAULT
  composite, // Composite (Best Available: user, critic, community)
  critic,    // Critic Score (Metacritic/OpenCritic)
  user,      // Personal User Score
}

/// Offline media storage tiers for covers, fanarts, and microtrailers.
enum MediaStorageTier {
  cacheOnly,        // Cache Only (On-demand as items are viewed) - DEFAULT
  coversAndFanarts, // Full Offline Covers & Fanarts (~1.28 GB)
  completeOffline,  // Complete Offline with Videos (~3.5 GB)
}

/// User preferences for the game gallery, media, and library display.
class GallerySettings {
  final bool includeUserHiddenGames;
  final bool includeDuplicateHiderGames;
  final String defaultViewMode; // 'grid', 'list', 'details'
  final RatingScoreSource ratingScoreSource;
  final MediaStorageTier mediaStorageTier;
  final bool autoPlayMicrotrailers;
  final bool microtrailerMuted;
  final bool showVideoScrubBar;
  final bool autoStreamTrailersInHero;

  /// Backwards-compatible getter: true if either hidden category is included.
  bool get showHiddenGames => includeUserHiddenGames || includeDuplicateHiderGames;

  const GallerySettings({
    this.includeUserHiddenGames = false,
    this.includeDuplicateHiderGames = false,
    bool? showHiddenGames,
    this.defaultViewMode = 'grid',
    this.ratingScoreSource = RatingScoreSource.community,
    this.mediaStorageTier = MediaStorageTier.cacheOnly,
    this.autoPlayMicrotrailers = true,
    this.microtrailerMuted = true,
    this.showVideoScrubBar = true,
    this.autoStreamTrailersInHero = false,
  });

  GallerySettings copyWith({
    bool? includeUserHiddenGames,
    bool? includeDuplicateHiderGames,
    bool? showHiddenGames,
    String? defaultViewMode,
    RatingScoreSource? ratingScoreSource,
    MediaStorageTier? mediaStorageTier,
    bool? autoPlayMicrotrailers,
    bool? microtrailerMuted,
    bool? showVideoScrubBar,
    bool? autoStreamTrailersInHero,
  }) {
    return GallerySettings(
      includeUserHiddenGames: includeUserHiddenGames ?? showHiddenGames ?? this.includeUserHiddenGames,
      includeDuplicateHiderGames: includeDuplicateHiderGames ?? this.includeDuplicateHiderGames,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      ratingScoreSource: ratingScoreSource ?? this.ratingScoreSource,
      mediaStorageTier: mediaStorageTier ?? this.mediaStorageTier,
      autoPlayMicrotrailers: autoPlayMicrotrailers ?? this.autoPlayMicrotrailers,
      microtrailerMuted: microtrailerMuted ?? this.microtrailerMuted,
      showVideoScrubBar: showVideoScrubBar ?? this.showVideoScrubBar,
      autoStreamTrailersInHero: autoStreamTrailersInHero ?? this.autoStreamTrailersInHero,
    );
  }

  Map<String, dynamic> toJson() => {
        'includeUserHiddenGames': includeUserHiddenGames,
        'includeDuplicateHiderGames': includeDuplicateHiderGames,
        'showHiddenGames': showHiddenGames,
        'defaultViewMode': defaultViewMode,
        'ratingScoreSource': ratingScoreSource.name,
        'mediaStorageTier': mediaStorageTier.name,
        'autoPlayMicrotrailers': autoPlayMicrotrailers,
        'microtrailerMuted': microtrailerMuted,
        'showVideoScrubBar': showVideoScrubBar,
        'autoStreamTrailersInHero': autoStreamTrailersInHero,
      };

  factory GallerySettings.fromJson(Map<String, dynamic> json) {
    final scoreSourceName = json['ratingScoreSource'] as String?;
    final scoreSource = RatingScoreSource.values.firstWhere(
      (e) => e.name == scoreSourceName,
      orElse: () => RatingScoreSource.community,
    );

    final tierName = json['mediaStorageTier'] as String?;
    final mediaTier = MediaStorageTier.values.firstWhere(
      (e) => e.name == tierName,
      orElse: () => MediaStorageTier.cacheOnly,
    );

    final legacyShowHidden = json['showHiddenGames'] as bool? ?? false;
    final includeUserHidden = json['includeUserHiddenGames'] as bool? ?? legacyShowHidden;
    final includeDuplicateHider = json['includeDuplicateHiderGames'] as bool? ?? false;

    return GallerySettings(
      includeUserHiddenGames: includeUserHidden,
      includeDuplicateHiderGames: includeDuplicateHider,
      defaultViewMode: json['defaultViewMode'] as String? ?? 'grid',
      ratingScoreSource: scoreSource,
      mediaStorageTier: mediaTier,
      autoPlayMicrotrailers: json['autoPlayMicrotrailers'] as bool? ?? true,
      microtrailerMuted: json['microtrailerMuted'] as bool? ?? true,
      showVideoScrubBar: json['showVideoScrubBar'] as bool? ?? true,
      autoStreamTrailersInHero: json['autoStreamTrailersInHero'] as bool? ?? json['auto_stream_trailers_in_hero'] as bool? ?? false,
    );
  }
}

/// Aggregated byte sizes of media tiers computed dynamically from sync metadata.
class MediaTierSizes {
  final int? coversAndFanartsBytes;
  final int? completeOfflineBytes;

  const MediaTierSizes({
    this.coversAndFanartsBytes,
    this.completeOfflineBytes,
  });

  bool get hasData =>
      (coversAndFanartsBytes != null && coversAndFanartsBytes! > 0) ||
      (completeOfflineBytes != null && completeOfflineBytes! > 0);
}

/// Repository for persisting GallerySettings and calculated media tier metrics into SQLite manifest_meta.
class GallerySettingsRepository {
  final AppDatabase database;
  static const String _settingsKey = 'gallery_settings';
  static const String _tierSizesKey = 'media_tier_sizes';

  GallerySettingsRepository(this.database);

  Future<GallerySettings> loadSettings() async {
    try {
      final results = await database.db.query(
        'manifest_meta',
        where: 'key = ?',
        whereArgs: [_settingsKey],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final jsonText = results.first['value_json'] as String;
        final json = jsonDecode(jsonText) as Map<String, dynamic>;
        return GallerySettings.fromJson(json);
      }
    } catch (e) {
      debugPrint('Error loading gallery settings: $e');
    }
    return const GallerySettings();
  }

  Future<void> saveSettings(GallerySettings settings) async {
    try {
      await database.db.insert(
        'manifest_meta',
        {
          'key': _settingsKey,
          'value_json': jsonEncode(settings.toJson()),
          'updated_utc': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error saving gallery settings: $e');
      rethrow;
    }
  }

  Future<MediaTierSizes> loadMediaTierSizes() async {
    try {
      final results = await database.db.query(
        'manifest_meta',
        where: 'key = ?',
        whereArgs: [_tierSizesKey],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final jsonText = results.first['value_json'] as String;
        final json = jsonDecode(jsonText) as Map<String, dynamic>;
        return MediaTierSizes(
          coversAndFanartsBytes: (json['covers_and_fanarts_bytes'] as num?)?.toInt(),
          completeOfflineBytes: (json['complete_offline_bytes'] as num?)?.toInt(),
        );
      }
    } catch (e) {
      debugPrint('Error loading media tier sizes: $e');
    }
    return const MediaTierSizes();
  }

  Future<void> saveMediaTierSizes({
    required int coversAndFanartsBytes,
    required int completeOfflineBytes,
  }) async {
    try {
      await database.db.insert(
        'manifest_meta',
        {
          'key': _tierSizesKey,
          'value_json': jsonEncode({
            'covers_and_fanarts_bytes': coversAndFanartsBytes,
            'complete_offline_bytes': completeOfflineBytes,
          }),
          'updated_utc': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error saving media tier sizes: $e');
    }
  }
}

