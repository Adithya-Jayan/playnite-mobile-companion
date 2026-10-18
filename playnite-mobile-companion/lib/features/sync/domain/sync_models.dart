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
  final bool isCancelled;
  final int downloadedCount;
  final int deletedCount;
  final int bytesTransferred;
  final int durationMs;
  final String? errorMessage;

  const SyncReport({
    required this.isSuccess,
    this.isCancelled = false,
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

  factory SyncReport.cancelled({
    required int downloadedCount,
    required int bytesTransferred,
    int durationMs = 0,
  }) => SyncReport(
    isSuccess: false,
    isCancelled: true,
    downloadedCount: downloadedCount,
    deletedCount: 0,
    bytesTransferred: bytesTransferred,
    durationMs: durationMs,
    errorMessage: 'Sync cancelled by user.',
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
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Represents an external hyperlink
class LinkItem {
  final String name;
  final String url;

  const LinkItem({required this.name, required this.url});

  factory LinkItem.fromJson(Map<String, dynamic> json) => LinkItem(
    name: json['name']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'name': name, 'url': url};
}

/// Represents media references in UnifiedGamePayload
class MediaPayload {
  final String? coverRelativePath;
  final String? coverSha256;
  final String? coverDriveFileId;

  final String? backgroundRelativePath;
  final String? backgroundSha256;
  final String? backgroundDriveFileId;

  final String? iconRelativePath;
  final String? iconSha256;
  final String? iconDriveFileId;

  final String? logoRelativePath;
  final String? logoDriveFileId;

  final String? microtrailerRelativePath;
  final String? microtrailerDriveFileId;

  final String? trailerRelativePath;
  final String? trailerDriveFileId;
  final String? trailerWebUrl;

  const MediaPayload({
    this.coverRelativePath,
    this.coverSha256,
    this.coverDriveFileId,
    this.backgroundRelativePath,
    this.backgroundSha256,
    this.backgroundDriveFileId,
    this.iconRelativePath,
    this.iconSha256,
    this.iconDriveFileId,
    this.logoRelativePath,
    this.logoDriveFileId,
    this.microtrailerRelativePath,
    this.microtrailerDriveFileId,
    this.trailerRelativePath,
    this.trailerDriveFileId,
    this.trailerWebUrl,
  });

  MediaPayload copyWith({
    String? coverRelativePath,
    String? coverSha256,
    String? coverDriveFileId,
    String? backgroundRelativePath,
    String? backgroundSha256,
    String? backgroundDriveFileId,
    String? iconRelativePath,
    String? iconSha256,
    String? iconDriveFileId,
    String? logoRelativePath,
    String? logoDriveFileId,
    String? microtrailerRelativePath,
    String? microtrailerDriveFileId,
    String? trailerRelativePath,
    String? trailerDriveFileId,
    String? trailerWebUrl,
  }) {
    return MediaPayload(
      coverRelativePath: coverRelativePath ?? this.coverRelativePath,
      coverSha256: coverSha256 ?? this.coverSha256,
      coverDriveFileId: coverDriveFileId ?? this.coverDriveFileId,
      backgroundRelativePath: backgroundRelativePath ?? this.backgroundRelativePath,
      backgroundSha256: backgroundSha256 ?? this.backgroundSha256,
      backgroundDriveFileId: backgroundDriveFileId ?? this.backgroundDriveFileId,
      iconRelativePath: iconRelativePath ?? this.iconRelativePath,
      iconSha256: iconSha256 ?? this.iconSha256,
      iconDriveFileId: iconDriveFileId ?? this.iconDriveFileId,
      logoRelativePath: logoRelativePath ?? this.logoRelativePath,
      logoDriveFileId: logoDriveFileId ?? this.logoDriveFileId,
      microtrailerRelativePath: microtrailerRelativePath ?? this.microtrailerRelativePath,
      microtrailerDriveFileId: microtrailerDriveFileId ?? this.microtrailerDriveFileId,
      trailerRelativePath: trailerRelativePath ?? this.trailerRelativePath,
      trailerDriveFileId: trailerDriveFileId ?? this.trailerDriveFileId,
      trailerWebUrl: trailerWebUrl ?? this.trailerWebUrl,
    );
  }

  factory MediaPayload.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MediaPayload();
    final cover = json['cover'] as Map<String, dynamic>?;
    final bg = json['background'] as Map<String, dynamic>?;
    final icon = json['icon'] as Map<String, dynamic>?;
    final logo = json['logo'] as Map<String, dynamic>?;
    final micro = json['microtrailer'] as Map<String, dynamic>?;
    final trailer = json['trailer'] as Map<String, dynamic>?;

    return MediaPayload(
      coverRelativePath: cover?['relative_path']?.toString(),
      coverSha256: cover?['sha256']?.toString(),
      coverDriveFileId: cover?['drive_file_id']?.toString(),
      backgroundRelativePath: bg?['relative_path']?.toString(),
      backgroundSha256: bg?['sha256']?.toString(),
      backgroundDriveFileId: bg?['drive_file_id']?.toString(),
      iconRelativePath: icon?['relative_path']?.toString(),
      iconSha256: icon?['sha256']?.toString(),
      iconDriveFileId: icon?['drive_file_id']?.toString(),
      logoRelativePath: logo?['relative_path']?.toString(),
      logoDriveFileId: logo?['drive_file_id']?.toString(),
      microtrailerRelativePath: micro?['relative_path']?.toString(),
      microtrailerDriveFileId: micro?['drive_file_id']?.toString(),
      trailerRelativePath: trailer?['relative_path']?.toString(),
      trailerDriveFileId: trailer?['drive_file_id']?.toString(),
      trailerWebUrl: trailer?['web_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'cover': {
      'relative_path': coverRelativePath,
      'sha256': coverSha256,
      'drive_file_id': coverDriveFileId,
    },
    'background': {
      'relative_path': backgroundRelativePath,
      'sha256': backgroundSha256,
      'drive_file_id': backgroundDriveFileId,
    },
    'icon': {
      'relative_path': iconRelativePath,
      'sha256': iconSha256,
      'drive_file_id': iconDriveFileId,
    },
    'logo': {
      'relative_path': logoRelativePath,
      'drive_file_id': logoDriveFileId,
    },
    'microtrailer': {
      'relative_path': microtrailerRelativePath,
      'drive_file_id': microtrailerDriveFileId,
    },
    'trailer': {
      'relative_path': trailerRelativePath,
      'drive_file_id': trailerDriveFileId,
      'web_url': trailerWebUrl,
    },
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
  final String? duplicateGroupId;
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
  final List<NamedItem> series;
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
    this.duplicateGroupId,
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
    this.series = const [],
    this.links = const [],
    this.media = const MediaPayload(),
    this.addons = const {},
  });

  UnifiedGamePayload copyWith({
    String? id,
    String? gameId,
    String? pluginId,
    String? name,
    String? sortingName,
    String? description,
    String? notes,
    int? playtimeSeconds,
    int? playCount,
    String? addedUtc,
    String? modifiedUtc,
    String? lastActivityUtc,
    String? recentActivityUtc,
    String? releaseDate,
    bool? isInstalled,
    String? installDirectory,
    int? installSizeBytes,
    bool? hidden,
    bool? isDuplicate,
    String? duplicateGroupId,
    List<DuplicateCopyPayload>? otherCopies,
    bool? favorite,
    int? userScore,
    int? criticScore,
    int? communityScore,
    String? version,
    NamedItem? source,
    NamedItem? completionStatus,
    List<NamedItem>? platforms,
    List<NamedItem>? genres,
    List<NamedItem>? categories,
    List<NamedItem>? tags,
    List<NamedItem>? developers,
    List<NamedItem>? publishers,
    List<NamedItem>? features,
    List<NamedItem>? series,
    List<LinkItem>? links,
    MediaPayload? media,
    Map<String, dynamic>? addons,
  }) {
    return UnifiedGamePayload(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      sortingName: sortingName ?? this.sortingName,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      playtimeSeconds: playtimeSeconds ?? this.playtimeSeconds,
      playCount: playCount ?? this.playCount,
      addedUtc: addedUtc ?? this.addedUtc,
      modifiedUtc: modifiedUtc ?? this.modifiedUtc,
      lastActivityUtc: lastActivityUtc ?? this.lastActivityUtc,
      recentActivityUtc: recentActivityUtc ?? this.recentActivityUtc,
      releaseDate: releaseDate ?? this.releaseDate,
      isInstalled: isInstalled ?? this.isInstalled,
      installDirectory: installDirectory ?? this.installDirectory,
      installSizeBytes: installSizeBytes ?? this.installSizeBytes,
      hidden: hidden ?? this.hidden,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      duplicateGroupId: duplicateGroupId ?? this.duplicateGroupId,
      otherCopies: otherCopies ?? this.otherCopies,
      favorite: favorite ?? this.favorite,
      userScore: userScore ?? this.userScore,
      criticScore: criticScore ?? this.criticScore,
      communityScore: communityScore ?? this.communityScore,
      version: version ?? this.version,
      source: source ?? this.source,
      completionStatus: completionStatus ?? this.completionStatus,
      platforms: platforms ?? this.platforms,
      genres: genres ?? this.genres,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      developers: developers ?? this.developers,
      publishers: publishers ?? this.publishers,
      features: features ?? this.features,
      series: series ?? this.series,
      links: links ?? this.links,
      media: media ?? this.media,
      addons: addons ?? this.addons,
    );
  }

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
      id: json['id']?.toString() ?? '',
      gameId: json['game_id']?.toString() ?? '',
      pluginId: json['plugin_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sortingName: json['sorting_name']?.toString() ?? json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      notes: json['notes']?.toString(),
      playtimeSeconds: (json['playtime_seconds'] as num?)?.toInt() ?? 0,
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
      addedUtc: json['added_utc']?.toString(),
      modifiedUtc: json['modified_utc']?.toString(),
      lastActivityUtc: json['last_activity_utc']?.toString(),
      recentActivityUtc: json['recent_activity_utc']?.toString(),
      releaseDate: json['release_date']?.toString(),
      isInstalled: parseBool(json['is_installed']),
      installDirectory: json['install_directory']?.toString(),
      installSizeBytes: (json['install_size_bytes'] as num?)?.toInt(),
      hidden: parseBool(json['hidden']),
      isDuplicate: parseBool(json['is_duplicate']),
      duplicateGroupId: json['duplicate_group_id']?.toString(),
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
      version: json['version']?.toString(),
      source: json['source'] != null && json['source'] is Map<String, dynamic>
          ? NamedItem.fromJson(json['source'] as Map<String, dynamic>)
          : null,
      completionStatus: json['completion_status'] != null && json['completion_status'] is Map<String, dynamic>
          ? NamedItem.fromJson(json['completion_status'] as Map<String, dynamic>)
          : null,
      platforms: parseNamedList(json['platforms']),
      genres: parseNamedList(json['genres']),
      categories: parseNamedList(json['categories']),
      tags: parseNamedList(json['tags']),
      developers: parseNamedList(json['developers']),
      publishers: parseNamedList(json['publishers']),
      features: parseNamedList(json['features']),
      series: parseNamedList(json['series']),
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
      'duplicate_group_id': duplicateGroupId,
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
      'icon_drive_file_id': media.iconDriveFileId,
      'icon_sha256': media.iconSha256,
      'logo_drive_file_id': media.logoDriveFileId,
      'microtrailer_drive_file_id': media.microtrailerDriveFileId,
      'trailer_drive_file_id': media.trailerDriveFileId,
      'trailer_web_url': media.trailerWebUrl,
      'platforms_json': jsonEncode(platforms.map((e) => e.toJson()).toList()),
      'genres_json': jsonEncode(genres.map((e) => e.toJson()).toList()),
      'categories_json': jsonEncode(categories.map((e) => e.toJson()).toList()),
      'tags_json': jsonEncode(tags.map((e) => e.toJson()).toList()),
      'developers_json': jsonEncode(developers.map((e) => e.toJson()).toList()),
      'publishers_json': jsonEncode(publishers.map((e) => e.toJson()).toList()),
      'features_json': jsonEncode(features.map((e) => e.toJson()).toList()),
      'series_json': jsonEncode(series.map((e) => e.toJson()).toList()),
      'links_json': jsonEncode(links.map((e) => e.toJson()).toList()),
      'addons_json': _safeAddonsJson(addons),
    };
  }

  static String _safeAddonsJson(Map<String, dynamic> rawAddons) {
    if (rawAddons.isEmpty) return '{}';
    try {
      final encoded = jsonEncode(rawAddons);
      // Safe threshold: Keep under 300 KB to guarantee fit in any SQLite cursor window
      if (encoded.length < 300 * 1024) return encoded;

      // If oversized (e.g. 1000+ achievements or thousands of session logs),
      // keep metadata/counters while truncating large nested item arrays to top 50
      final sanitized = <String, dynamic>{};
      rawAddons.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final copy = Map<String, dynamic>.from(value);
          copy.forEach((subKey, subValue) {
            if (subValue is List && subValue.length > 50) {
              copy[subKey] = subValue.sublist(0, 50);
            }
          });
          sanitized[key] = copy;
        } else {
          sanitized[key] = value;
        }
      });
      return jsonEncode(sanitized);
    } catch (_) {
      return '{}';
    }
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
    'is_duplicate': isDuplicate,
    if (duplicateGroupId != null) 'duplicate_group_id': duplicateGroupId,
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
    'series': series.map((e) => e.toJson()).toList(),
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
    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return false;
    }

    return DuplicateCopyPayload(
      id: json['id']?.toString() ?? '',
      gameId: json['game_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sourceName: json['source_name']?.toString() ?? 'Playnite',
      isInstalled: parseBool(json['is_installed']),
      playtimeSeconds: (json['playtime_seconds'] as num?)?.toInt() ?? 0,
      installDirectory: json['install_directory']?.toString(),
      hidden: parseBool(json['hidden']),
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
