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
  final bool showHiddenGames;
  final String defaultViewMode; // 'grid', 'list', 'details'
  final RatingScoreSource ratingScoreSource;
  final MediaStorageTier mediaStorageTier;
  final bool autoPlayMicrotrailers;
  final bool microtrailerMuted;
  final bool showVideoScrubBar;

  const GallerySettings({
    this.showHiddenGames = false,
    this.defaultViewMode = 'grid',
    this.ratingScoreSource = RatingScoreSource.community,
    this.mediaStorageTier = MediaStorageTier.cacheOnly,
    this.autoPlayMicrotrailers = true,
    this.microtrailerMuted = true,
    this.showVideoScrubBar = true,
  });

  GallerySettings copyWith({
    bool? showHiddenGames,
    String? defaultViewMode,
    RatingScoreSource? ratingScoreSource,
    MediaStorageTier? mediaStorageTier,
    bool? autoPlayMicrotrailers,
    bool? microtrailerMuted,
    bool? showVideoScrubBar,
  }) {
    return GallerySettings(
      showHiddenGames: showHiddenGames ?? this.showHiddenGames,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      ratingScoreSource: ratingScoreSource ?? this.ratingScoreSource,
      mediaStorageTier: mediaStorageTier ?? this.mediaStorageTier,
      autoPlayMicrotrailers: autoPlayMicrotrailers ?? this.autoPlayMicrotrailers,
      microtrailerMuted: microtrailerMuted ?? this.microtrailerMuted,
      showVideoScrubBar: showVideoScrubBar ?? this.showVideoScrubBar,
    );
  }

  Map<String, dynamic> toJson() => {
        'showHiddenGames': showHiddenGames,
        'defaultViewMode': defaultViewMode,
        'ratingScoreSource': ratingScoreSource.name,
        'mediaStorageTier': mediaStorageTier.name,
        'autoPlayMicrotrailers': autoPlayMicrotrailers,
        'microtrailerMuted': microtrailerMuted,
        'showVideoScrubBar': showVideoScrubBar,
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

    return GallerySettings(
      showHiddenGames: json['showHiddenGames'] as bool? ?? false,
      defaultViewMode: json['defaultViewMode'] as String? ?? 'grid',
      ratingScoreSource: scoreSource,
      mediaStorageTier: mediaTier,
      autoPlayMicrotrailers: json['autoPlayMicrotrailers'] as bool? ?? true,
      microtrailerMuted: json['microtrailerMuted'] as bool? ?? true,
      showVideoScrubBar: json['showVideoScrubBar'] as bool? ?? true,
    );
  }
}

/// Repository for persisting GallerySettings into SQLite manifest_meta.
class GallerySettingsRepository {
  final AppDatabase database;
  static const String _settingsKey = 'gallery_settings';

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
}
