import 'dart:convert';

/// Represents a single entry in sync_index.json
class IndexEntry {
  final String relativePath;
  final String sha256;
  final int sizeBytes;
  final String modifiedUtc;
  final String driveFileId;
  final String mimeType;
  final String category;
  final String? gameId;

  const IndexEntry({
    required this.relativePath,
    required this.sha256,
    required this.sizeBytes,
    required this.modifiedUtc,
    required this.driveFileId,
    required this.mimeType,
    required this.category,
    this.gameId,
  });

  factory IndexEntry.fromJson(String relativePath, Map<String, dynamic> json) {
    return IndexEntry(
      relativePath: relativePath,
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      modifiedUtc: json['modified_utc'] as String? ?? '',
      driveFileId: json['drive_file_id'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      category: json['category'] as String? ?? 'unknown',
      gameId: json['game_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'sha256': sha256,
    'size_bytes': sizeBytes,
    'modified_utc': modifiedUtc,
    'drive_file_id': driveFileId,
    'mime_type': mimeType,
    'category': category,
    if (gameId != null) 'game_id': gameId,
  };
}

/// Represents the root sync_index.json document
class SyncIndex {
  final String version;
  final String generator;
  final String generatedAtUtc;
  final String libraryId;
  final int totalGames;
  final int totalEntries;
  final int totalSizeBytes;
  final Map<String, IndexEntry> entries;

  const SyncIndex({
    required this.version,
    required this.generator,
    required this.generatedAtUtc,
    required this.libraryId,
    required this.totalGames,
    required this.totalEntries,
    required this.totalSizeBytes,
    required this.entries,
  });

  factory SyncIndex.fromJson(Map<String, dynamic> json) {
    final entriesRaw = json['entries'] as Map<String, dynamic>? ?? {};
    final entriesMap = <String, IndexEntry>{};

    entriesRaw.forEach((path, val) {
      if (val is Map<String, dynamic>) {
        entriesMap[path] = IndexEntry.fromJson(path, val);
      }
    });

    return SyncIndex(
      version: json['version'] as String? ?? '1.0.0',
      generator: json['generator'] as String? ?? '',
      generatedAtUtc: json['generated_at_utc'] as String? ?? '',
      libraryId: json['library_id'] as String? ?? '',
      totalGames: (json['total_games'] as num?)?.toInt() ?? 0,
      totalEntries: (json['total_entries'] as num?)?.toInt() ?? 0,
      totalSizeBytes: (json['total_size_bytes'] as num?)?.toInt() ?? 0,
      entries: entriesMap,
    );
  }
}

/// Result of diffing remote sync index against local state.
class PullDiff {
  final List<IndexEntry> toDownload;
  final List<String> toDelete; // relative paths to delete locally
  final int totalDownloadBytes;

  const PullDiff({
    required this.toDownload,
    required this.toDelete,
    required this.totalDownloadBytes,
  });

  bool get isNoOp => toDownload.isEmpty && toDelete.isEmpty;
}

/// Final summary report returned after delta pull execution.
class SyncReport {
  final bool isSuccess;
  final int downloadedCount;
  final int deletedCount;
  final int bytesTransferred;
  final int durationMs;
  final String? errorMessage;

  const SyncReport({
    required this.isSuccess,
    required this.downloadedCount,
    required this.deletedCount,
    required this.bytesTransferred,
    required this.durationMs,
    this.errorMessage,
  });

  factory SyncReport.noOp({int durationMs = 0}) => SyncReport(
    isSuccess: true,
    downloadedCount: 0,
    deletedCount: 0,
    bytesTransferred: 0,
    durationMs: durationMs,
  );

  factory SyncReport.failure(String message, {int durationMs = 0}) => SyncReport(
    isSuccess: false,
    downloadedCount: 0,
    deletedCount: 0,
    bytesTransferred: 0,
    durationMs: durationMs,
    errorMessage: message,
  );
}

/// Represents the ongoing sync status for UI progress reporting.
enum SyncPhase {
  idle,
  fetchingIndex,
  computingDiff,
  downloadingPayloads,
  committingDatabase,
  completed,
  error,
}

class SyncProgress {
  final SyncPhase phase;
  final int current;
  final int total;
  final int bytesDownloaded;
  final int totalBytes;
  final String message;
  final String? currentItem;
  final String? etaText;
  final String? stepText;

  const SyncProgress({
    this.phase = SyncPhase.idle,
    this.current = 0,
    this.total = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.message = '',
    this.currentItem,
    this.etaText,
    this.stepText,
  });

  SyncProgress copyWith({
    SyncPhase? phase,
    int? current,
    int? total,
    int? bytesDownloaded,
    int? totalBytes,
    String? message,
    String? currentItem,
    String? etaText,
    String? stepText,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      current: current ?? this.current,
      total: total ?? this.total,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      message: message ?? this.message,
      currentItem: currentItem ?? this.currentItem,
      etaText: etaText ?? this.etaText,
      stepText: stepText ?? this.stepText,
    );
  }
}

/// Represents named taxonomy items (Platform, Genre, Source, Tag, etc.)
class NamedItem {
  final String id;
  final String name;

  const NamedItem({required this.id, required this.name});

  factory NamedItem.fromJson(Map<String, dynamic> json) => NamedItem(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Represents an external hyperlink
class LinkItem {
  final String name;
  final String url;

  const LinkItem({required this.name, required this.url});

  factory LinkItem.fromJson(Map<String, dynamic> json) => LinkItem(
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

/// Represents media references in UnifiedGamePayload
class MediaPayload {
  final String? coverSha256;
  final String? coverDriveFileId;
  final String? backgroundSha256;
  final String? backgroundDriveFileId;
  final String? logoDriveFileId;
  final String? microtrailerDriveFileId;
  final String? trailerDriveFileId;

  const MediaPayload({
    this.coverSha256,
    this.coverDriveFileId,
    this.backgroundSha256,
    this.backgroundDriveFileId,
    this.logoDriveFileId,
    this.microtrailerDriveFileId,
    this.trailerDriveFileId,
  });

  factory MediaPayload.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MediaPayload();
    final cover = json['cover'] as Map<String, dynamic>?;
    final bg = json['background'] as Map<String, dynamic>?;
    final logo = json['logo'] as Map<String, dynamic>?;
    final micro = json['microtrailer'] as Map<String, dynamic>?;
    final trailer = json['trailer'] as Map<String, dynamic>?;

    return MediaPayload(
      coverSha256: cover?['sha256'] as String?,
      coverDriveFileId: cover?['drive_file_id'] as String?,
      backgroundSha256: bg?['sha256'] as String?,
      backgroundDriveFileId: bg?['drive_file_id'] as String?,
      logoDriveFileId: logo?['drive_file_id'] as String?,
      microtrailerDriveFileId: micro?['drive_file_id'] as String?,
      trailerDriveFileId: trailer?['drive_file_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'cover': {'sha256': coverSha256, 'drive_file_id': coverDriveFileId},
    'background': {'sha256': backgroundSha256, 'drive_file_id': backgroundDriveFileId},
    'logo': {'drive_file_id': logoDriveFileId},
    'microtrailer': {'drive_file_id': microtrailerDriveFileId},
    'trailer': {'drive_file_id': trailerDriveFileId},
  };
}

/// Unified Game Payload parsed from games/{id}.json
class UnifiedGamePayload {
  final String id;
  final String gameId;
  final String pluginId;
  final String name;
  final String sortingName;
  final String? description;
  final String? notes;
  final int playtimeSeconds;
  final int playCount;
  final String? addedUtc;
  final String? modifiedUtc;
  final String? lastActivityUtc;
  final String? recentActivityUtc;
  final String? releaseDate;
  final bool isInstalled;
  final String? installDirectory;
  final int? installSizeBytes;
  final bool hidden;
  final bool isDuplicate;
  final List<DuplicateCopyPayload> otherCopies;
  final bool favorite;
  final int? userScore;
  final int? criticScore;
  final int? communityScore;
  final String? version;
  final NamedItem? source;
  final NamedItem? completionStatus;
  final List<NamedItem> platforms;
  final List<NamedItem> genres;
  final List<NamedItem> categories;
  final List<NamedItem> tags;
  final List<NamedItem> developers;
  final List<NamedItem> publishers;
  final List<NamedItem> features;
  final List<LinkItem> links;
  final MediaPayload media;
  final Map<String, dynamic> addons;

  const UnifiedGamePayload({
    required this.id,
    required this.gameId,
    required this.pluginId,
    required this.name,
    required this.sortingName,
    this.description,
    this.notes,
    this.playtimeSeconds = 0,
    this.playCount = 0,
    this.addedUtc,
    this.modifiedUtc,
    this.lastActivityUtc,
    this.recentActivityUtc,
    this.releaseDate,
    this.isInstalled = false,
    this.installDirectory,
    this.installSizeBytes,
    this.hidden = false,
    this.isDuplicate = false,
    this.otherCopies = const [],
    this.favorite = false,
    this.userScore,
    this.criticScore,
    this.communityScore,
    this.version,
    this.source,
    this.completionStatus,
    this.platforms = const [],
    this.genres = const [],
    this.categories = const [],
    this.tags = const [],
    this.developers = const [],
    this.publishers = const [],
    this.features = const [],
    this.links = const [],
    this.media = const MediaPayload(),
    this.addons = const {},
  });

  factory UnifiedGamePayload.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return false;
    }

    List<NamedItem> parseNamedList(dynamic list) {
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => NamedItem.fromJson(item))
          .toList();
    }

    List<LinkItem> parseLinks(dynamic list) {
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => LinkItem.fromJson(item))
          .toList();
    }

    return UnifiedGamePayload(
      id: json['id'] as String? ?? '',
      gameId: json['game_id'] as String? ?? '',
      pluginId: json['plugin_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sortingName: json['sorting_name'] as String? ?? json['name'] as String? ?? '',
      description: json['description'] as String?,
      notes: json['notes'] as String?,
      playtimeSeconds: (json['playtime_seconds'] as num?)?.toInt() ?? 0,
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
      addedUtc: json['added_utc'] as String?,
      modifiedUtc: json['modified_utc'] as String?,
      lastActivityUtc: json['last_activity_utc'] as String?,
      recentActivityUtc: json['recent_activity_utc'] as String?,
      releaseDate: json['release_date'] as String?,
      isInstalled: parseBool(json['is_installed']),
      installDirectory: json['install_directory'] as String?,
      installSizeBytes: (json['install_size_bytes'] as num?)?.toInt(),
      hidden: parseBool(json['hidden']),
      isDuplicate: parseBool(json['is_duplicate']),
      otherCopies: (json['other_copies'] is List)
          ? (json['other_copies'] as List)
              .whereType<Map<String, dynamic>>()
              .map((e) => DuplicateCopyPayload.fromJson(e))
              .toList()
          : const [],
      favorite: parseBool(json['favorite']),
      userScore: (json['user_score'] as num?)?.toInt(),
      criticScore: (json['critic_score'] as num?)?.toInt(),
      communityScore: (json['community_score'] as num?)?.toInt(),
      version: json['version'] as String?,
      source: json['source'] != null ? NamedItem.fromJson(json['source']) : null,
      completionStatus: json['completion_status'] != null
          ? NamedItem.fromJson(json['completion_status'])
          : null,
      platforms: parseNamedList(json['platforms']),
      genres: parseNamedList(json['genres']),
      categories: parseNamedList(json['categories']),
      tags: parseNamedList(json['tags']),
      developers: parseNamedList(json['developers']),
      publishers: parseNamedList(json['publishers']),
      features: parseNamedList(json['features']),
      links: parseLinks(json['links']),
      media: MediaPayload.fromJson(json['media'] as Map<String, dynamic>?),
      addons: json['addons'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toDatabaseRow() {
    return {
      'id': id,
      'game_id': gameId,
      'plugin_id': pluginId,
      'name': name,
      'sorting_name': sortingName,
      'description': description,
      'notes': notes,
      'playtime_seconds': playtimeSeconds,
      'play_count': playCount,
      'added_utc': addedUtc,
      'modified_utc': modifiedUtc,
      'last_activity_utc': lastActivityUtc,
      'recent_activity_utc': recentActivityUtc,
      'release_date': releaseDate,
      'is_installed': isInstalled ? 1 : 0,
      'install_directory': installDirectory,
      'install_size_bytes': installSizeBytes,
      'hidden': hidden ? 1 : 0,
      'is_duplicate': isDuplicate ? 1 : 0,
      'other_copies_json': jsonEncode(otherCopies.map((e) => e.toJson()).toList()),
      'favorite': favorite ? 1 : 0,
      'user_score': userScore,
      'critic_score': criticScore,
      'community_score': communityScore,
      'version': version,
      'source_id': source?.id,
      'source_name': source?.name,
      'completion_status_id': completionStatus?.id,
      'completion_status_name': completionStatus?.name,
      'cover_drive_file_id': media.coverDriveFileId,
      'cover_sha256': media.coverSha256,
      'background_drive_file_id': media.backgroundDriveFileId,
      'background_sha256': media.backgroundSha256,
      'logo_drive_file_id': media.logoDriveFileId,
      'microtrailer_drive_file_id': media.microtrailerDriveFileId,
      'trailer_drive_file_id': media.trailerDriveFileId,
      'platforms_json': jsonEncode(platforms.map((e) => e.toJson()).toList()),
      'genres_json': jsonEncode(genres.map((e) => e.toJson()).toList()),
      'categories_json': jsonEncode(categories.map((e) => e.toJson()).toList()),
      'tags_json': jsonEncode(tags.map((e) => e.toJson()).toList()),
      'developers_json': jsonEncode(developers.map((e) => e.toJson()).toList()),
      'publishers_json': jsonEncode(publishers.map((e) => e.toJson()).toList()),
      'features_json': jsonEncode(features.map((e) => e.toJson()).toList()),
      'links_json': jsonEncode(links.map((e) => e.toJson()).toList()),
      'addons_json': jsonEncode(addons),
    };
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'game_id': gameId,
    'plugin_id': pluginId,
    'name': name,
    'sorting_name': sortingName,
    if (description != null) 'description': description,
    if (notes != null) 'notes': notes,
    'playtime_seconds': playtimeSeconds,
    'play_count': playCount,
    if (addedUtc != null) 'added_utc': addedUtc,
    if (modifiedUtc != null) 'modified_utc': modifiedUtc,
    if (lastActivityUtc != null) 'last_activity_utc': lastActivityUtc,
    if (recentActivityUtc != null) 'recent_activity_utc': recentActivityUtc,
    if (releaseDate != null) 'release_date': releaseDate,
    'is_installed': isInstalled,
    if (installDirectory != null) 'install_directory': installDirectory,
    if (installSizeBytes != null) 'install_size_bytes': installSizeBytes,
    'hidden': hidden,
    'favorite': favorite,
    if (userScore != null) 'user_score': userScore,
    if (criticScore != null) 'critic_score': criticScore,
    if (communityScore != null) 'community_score': communityScore,
    if (version != null) 'version': version,
    if (source != null) 'source': source!.toJson(),
    if (completionStatus != null) 'completion_status': completionStatus!.toJson(),
    'platforms': platforms.map((e) => e.toJson()).toList(),
    'genres': genres.map((e) => e.toJson()).toList(),
    'categories': categories.map((e) => e.toJson()).toList(),
    'tags': tags.map((e) => e.toJson()).toList(),
    'developers': developers.map((e) => e.toJson()).toList(),
    'publishers': publishers.map((e) => e.toJson()).toList(),
    'features': features.map((e) => e.toJson()).toList(),
    'links': links.map((e) => e.toJson()).toList(),
    'media': media.toJson(),
    'addons': addons,
  };
}

/// Supported storage and synchronization backends
enum SyncStorageType {
  googleDrive,
  localFolder,
  demo,
}

/// Configuration settings for sync operations
class SyncConfiguration {
  final SyncStorageType storageType;
  final String googleDriveFolderName;
  final String googleDriveFolderId;
  final String googleClientId;
  final String googleClientSecret;
  final String googleRefreshToken;
  final String googleAccessToken;
  final String localFolderPath;
  final String? lastSyncUtc;

  const SyncConfiguration({
    this.storageType = SyncStorageType.googleDrive,
    this.googleDriveFolderName = 'PlayniteSync',
    this.googleDriveFolderId = '',
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.googleRefreshToken = '',
    this.googleAccessToken = '',
    this.localFolderPath = '',
    this.lastSyncUtc,
  });

  bool get isGoogleDriveConfigured =>
      storageType == SyncStorageType.googleDrive &&
      (googleAccessToken.isNotEmpty || googleRefreshToken.isNotEmpty);

  SyncConfiguration copyWith({
    SyncStorageType? storageType,
    String? googleDriveFolderName,
    String? googleDriveFolderId,
    String? googleClientId,
    String? googleClientSecret,
    String? googleRefreshToken,
    String? googleAccessToken,
    String? localFolderPath,
    String? lastSyncUtc,
  }) {
    return SyncConfiguration(
      storageType: storageType ?? this.storageType,
      googleDriveFolderName: googleDriveFolderName ?? this.googleDriveFolderName,
      googleDriveFolderId: googleDriveFolderId ?? this.googleDriveFolderId,
      googleClientId: googleClientId ?? this.googleClientId,
      googleClientSecret: googleClientSecret ?? this.googleClientSecret,
      googleRefreshToken: googleRefreshToken ?? this.googleRefreshToken,
      googleAccessToken: googleAccessToken ?? this.googleAccessToken,
      localFolderPath: localFolderPath ?? this.localFolderPath,
      lastSyncUtc: lastSyncUtc ?? this.lastSyncUtc,
    );
  }

  Map<String, dynamic> toJson() => {
    'storage_type': storageType.name,
    'google_drive_folder_name': googleDriveFolderName,
    'google_drive_folder_id': googleDriveFolderId,
    'google_client_id': googleClientId,
    'google_client_secret': googleClientSecret,
    'google_refresh_token': googleRefreshToken,
    'google_access_token': googleAccessToken,
    'local_folder_path': localFolderPath,
    'last_sync_utc': lastSyncUtc,
  };

  factory SyncConfiguration.fromJson(Map<String, dynamic> json) {
    SyncStorageType type = SyncStorageType.googleDrive;
    final typeStr = json['storage_type'] as String?;
    if (typeStr != null) {
      for (final t in SyncStorageType.values) {
        if (t.name == typeStr) {
          type = t;
          break;
        }
      }
    }
    return SyncConfiguration(
      storageType: type,
      googleDriveFolderName: json['google_drive_folder_name'] as String? ?? 'PlayniteSync',
      googleDriveFolderId: json['google_drive_folder_id'] as String? ?? '',
      googleClientId: json['google_client_id'] as String? ?? '',
      googleClientSecret: json['google_client_secret'] as String? ?? '',
      googleRefreshToken: json['google_refresh_token'] as String? ?? '',
      googleAccessToken: json['google_access_token'] as String? ?? '',
      localFolderPath: json['local_folder_path'] as String? ?? '',
      lastSyncUtc: json['last_sync_utc'] as String?,
    );
  }
}

class DuplicateCopyPayload {
  final String id;
  final String gameId;
  final String name;
  final String sourceName;
  final bool isInstalled;
  final int playtimeSeconds;
  final String? installDirectory;
  final bool hidden;

  const DuplicateCopyPayload({
    required this.id,
    this.gameId = '',
    required this.name,
    this.sourceName = 'Playnite',
    this.isInstalled = false,
    this.playtimeSeconds = 0,
    this.installDirectory,
    this.hidden = false,
  });

  factory DuplicateCopyPayload.fromJson(Map<String, dynamic> json) {
    return DuplicateCopyPayload(
      id: json['id'] as String? ?? '',
      gameId: json['game_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? 'Playnite',
      isInstalled: json['is_installed'] as bool? ?? false,
      playtimeSeconds: (json['playtime_seconds'] as num?)?.toInt() ?? 0,
      installDirectory: json['install_directory'] as String?,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'game_id': gameId,
    'name': name,
    'source_name': sourceName,
    'is_installed': isInstalled,
    'playtime_seconds': playtimeSeconds,
    'install_directory': installDirectory,
    'hidden': hidden,
  };
}
