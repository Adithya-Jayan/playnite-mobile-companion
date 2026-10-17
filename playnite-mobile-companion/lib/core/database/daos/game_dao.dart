import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class GameDao {
  final AppDatabase database;

  GameDao(this.database);

  /// Ingests a batch of UnifiedGamePayload objects atomically.
  /// Unpacks known addons into child tables while preserving raw addons_json.
  Future<void> batchUpsertGames(List<UnifiedGamePayload> payloads, {Transaction? txn}) async {
    if (payloads.isEmpty) return;

    final executor = txn ?? database.db;
    final batch = executor.batch();

    for (final payload in payloads) {
      // 1. Insert or Replace in games table
      final row = payload.toDatabaseRow();
      batch.insert('games', row, conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Update FTS virtual table (only if FTS table is available)
      if (database.isFtsSupported) {
        final devText = payload.developers.map((e) => e.name).join(' ');
        final pubText = payload.publishers.map((e) => e.name).join(' ');
        final genText = payload.genres.map((e) => e.name).join(' ');
        final tagText = payload.tags.map((e) => e.name).join(' ');

        batch.delete('games_fts', where: 'id = ?', whereArgs: [payload.id]);
        batch.insert('games_fts', {
          'id': payload.id,
          'name': payload.name,
          'sorting_name': payload.sortingName,
          'description': payload.description ?? '',
          'developers': devText,
          'publishers': pubText,
          'genres': genText,
          'tags': tagText,
        });
      }

      // 3. Unpack SuccessStory (achievements)
      final successStory = payload.addons['success_story'] as Map<String, dynamic>?;
      if (successStory != null && successStory['achievements'] is List) {
        batch.delete('achievements', where: 'game_id = ?', whereArgs: [payload.id]);
        final achievements = successStory['achievements'] as List;
        for (final item in achievements) {
          if (item is Map<String, dynamic>) {
            batch.insert('achievements', {
              'game_id': payload.id,
              'api_name': item['api_name'] as String? ?? '',
              'name': item['name'] as String? ?? '',
              'description': item['description'] as String?,
              'url_unlocked': item['url_unlocked'] as String?,
              'url_locked': item['url_locked'] as String?,
              'date_unlocked_utc': item['date_unlocked_utc'] as String?,
              'percent': (item['percent'] as num?)?.toDouble(),
              'gamer_score': (item['gamer_score'] as num?)?.toDouble(),
              'is_hidden': (item['is_hidden'] as bool? ?? false) ? 1 : 0,
            });
          }
        }
      }

      // 4. Unpack GameActivity (play_sessions)
      final gameActivity = payload.addons['game_activity'] as Map<String, dynamic>?;
      if (gameActivity != null && gameActivity['sessions'] is List) {
        batch.delete('play_sessions', where: 'game_id = ?', whereArgs: [payload.id]);
        final sessions = gameActivity['sessions'] as List;
        for (final item in sessions) {
          if (item is Map<String, dynamic>) {
            batch.insert('play_sessions', {
              'game_id': payload.id,
              'date_session_utc': item['date_session_utc'] as String? ?? '',
              'elapsed_seconds': (item['elapsed_seconds'] as num?)?.toInt() ?? 0,
              'action_name': item['action_name'] as String?,
            });
          }
        }
      }

      // 5. Unpack HowLongToBeat (hltb_data)
      final hltb = payload.addons['how_long_to_beat'] as Map<String, dynamic>?;
      if (hltb != null) {
        batch.insert(
          'hltb_data',
          {
            'game_id': payload.id,
            'main_story_seconds': (hltb['main_story_seconds'] as num?)?.toInt(),
            'main_extra_seconds': (hltb['main_extra_seconds'] as num?)?.toInt(),
            'completionist_seconds': (hltb['completionist_seconds'] as num?)?.toInt(),
            'all_styles_seconds': (hltb['all_styles_seconds'] as num?)?.toInt(),
            'hltb_id': hltb['hltb_id'] as String?,
            'url': hltb['url'] as String?,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 6. Unpack CheckDlc (dlc_items)
      final checkDlc = payload.addons['check_dlc'] as Map<String, dynamic>?;
      if (checkDlc != null && checkDlc['dlcs'] is List) {
        batch.delete('dlc_items', where: 'game_id = ?', whereArgs: [payload.id]);
        final dlcs = checkDlc['dlcs'] as List;
        for (final item in dlcs) {
          if (item is Map<String, dynamic>) {
            batch.insert('dlc_items', {
              'game_id': payload.id,
              'dlc_id': item['dlc_id'] as String? ?? '',
              'name': item['name'] as String? ?? '',
              'is_owned': (item['is_owned'] as bool? ?? false) ? 1 : 0,
              'price': (item['price'] as num?)?.toDouble(),
              'currency': item['currency'] as String?,
              'url': item['url'] as String?,
              'image_url': item['image_url'] as String?,
            });
          }
        }
      }
    }

    await batch.commit(noResult: true);
  }

  /// Cascade deletes removed games from primary and child tables.
  Future<void> batchDeleteGames(List<String> gameIds, {Transaction? txn}) async {
    if (gameIds.isEmpty) return;

    final executor = txn ?? database.db;
    final batch = executor.batch();

    for (final id in gameIds) {
      batch.delete('games', where: 'id = ?', whereArgs: [id]);
      if (database.isFtsSupported) {
        batch.delete('games_fts', where: 'id = ?', whereArgs: [id]);
      }
      batch.delete('achievements', where: 'game_id = ?', whereArgs: [id]);
      batch.delete('play_sessions', where: 'game_id = ?', whereArgs: [id]);
      batch.delete('hltb_data', where: 'game_id = ?', whereArgs: [id]);
      batch.delete('dlc_items', where: 'game_id = ?', whereArgs: [id]);
    }

    await batch.commit(noResult: true);
  }

  /// Retrieves a single game by its internal Playnite ID.
  Future<UnifiedGamePayload?> getGameById(String id) async {
    final rows = await database.db.query(
      'games',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return _rowToPayload(rows.first);
    } catch (e) {
      debugPrint('Error deserializing game $id: $e');
      return null;
    }
  }

  /// Retrieves games count in the local database.
  Future<int> getGamesCount() async {
    final result = await database.db.rawQuery('SELECT COUNT(*) as count FROM games;');
    if (result.isNotEmpty && result.first['count'] is num) {
      return (result.first['count'] as num).toInt();
    }
    return 0;
  }

  /// Returns all game IDs currently in local database.
  Future<List<String>> getAllGameIds() async {
    final rows = await database.db.query('games', columns: ['id']);
    return rows.map((r) => r['id'] as String).toList();
  }

  /// High-performance multi-criteria library query supporting instant search and sorting.
  Future<List<UnifiedGamePayload>> getFilteredGames({
    required GameFilterCriteria criteria,
    required SortOption sort,
    int? limit,
    int? offset,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    // 1. Filter: Hidden games (exclude hidden by default unless includeHidden is true)
    if (!criteria.includeHidden) {
      whereClauses.add('(hidden = 0 OR hidden IS NULL)');
    }

    // 2. Search Query (FTS match or LIKE fallback)
    if (criteria.searchQuery.trim().isNotEmpty) {
      final sanitized = criteria.searchQuery.replaceAll("'", "''").trim();
      bool ftsSuccess = false;

      if (database.isFtsSupported) {
        try {
          // Attempt FTS query
          final ftsRows = await database.db.rawQuery(
            'SELECT id FROM games_fts WHERE games_fts MATCH ?;',
            ['"$sanitized*"'],
          );
          final matchIds = ftsRows.map((r) => r['id'] as String).toList();
          if (matchIds.isNotEmpty) {
            final placeholders = List.filled(matchIds.length, '?').join(',');
            whereClauses.add('id IN ($placeholders)');
            whereArgs.addAll(matchIds);
          } else {
            // If FTS returned 0, fallback to LIKE across name and sorting_name
            whereClauses.add('(name LIKE ? OR sorting_name LIKE ?)');
            whereArgs.addAll(['%$sanitized%', '%$sanitized%']);
          }
          ftsSuccess = true;
        } catch (e) {
          debugPrint('FTS query error, falling back to LIKE: $e');
        }
      }

      if (!ftsSuccess) {
        // Standard LIKE across name and sorting_name
        whereClauses.add('(name LIKE ? OR sorting_name LIKE ?)');
        whereArgs.addAll(['%$sanitized%', '%$sanitized%']);
      }
    }

    // 2. Filter: Sources
    if (criteria.sources.isNotEmpty) {
      final placeholders = List.filled(criteria.sources.length, '?').join(',');
      whereClauses.add('source_name IN ($placeholders)');
      whereArgs.addAll(criteria.sources);
    }

    // 3. Filter: Completion Statuses
    if (criteria.completionStatuses.isNotEmpty) {
      final placeholders = List.filled(criteria.completionStatuses.length, '?').join(',');
      whereClauses.add('completion_status_name IN ($placeholders)');
      whereArgs.addAll(criteria.completionStatuses);
    }

    // 4. Filter: Is Installed
    if (criteria.isInstalled != null) {
      whereClauses.add('is_installed = ?');
      whereArgs.add(criteria.isInstalled! ? 1 : 0);
    }

    // 5. Filter: Is Favorite
    if (criteria.isFavorite != null) {
      whereClauses.add('favorite = ?');
      whereArgs.add(criteria.isFavorite! ? 1 : 0);
    }

    // 6. Filter: User Score Range
    if (criteria.minScore != null) {
      whereClauses.add('user_score >= ?');
      whereArgs.add(criteria.minScore);
    }
    if (criteria.maxScore != null) {
      whereClauses.add('user_score <= ?');
      whereArgs.add(criteria.maxScore);
    }

    // 7. Filter: Platforms (JSON containment via LIKE)
    if (criteria.platforms.isNotEmpty) {
      final platformSubClauses = <String>[];
      for (final p in criteria.platforms) {
        platformSubClauses.add('platforms_json LIKE ?');
        whereArgs.add('%"name":"$p"%');
      }
      whereClauses.add('(${platformSubClauses.join(' OR ')})');
    }

    // 8. Filter: Genres (JSON containment via LIKE)
    if (criteria.genres.isNotEmpty) {
      final genreSubClauses = <String>[];
      for (final g in criteria.genres) {
        genreSubClauses.add('genres_json LIKE ?');
        whereArgs.add('%"name":"$g"%');
      }
      whereClauses.add('(${genreSubClauses.join(' OR ')})');
    }

    // 9. Filter: Tags (JSON containment via LIKE)
    if (criteria.tags.isNotEmpty) {
      final tagSubClauses = <String>[];
      for (final t in criteria.tags) {
        tagSubClauses.add('tags_json LIKE ?');
        whereArgs.add('%"name":"$t"%');
      }
      whereClauses.add('(${tagSubClauses.join(' OR ')})');
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    final orderBy = sort.toSqlOrderBy();

    final rows = await database.db.query(
      'games',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    final games = <UnifiedGamePayload>[];
    for (final row in rows) {
      try {
        games.add(_rowToPayload(row));
      } catch (e, stack) {
        debugPrint('Warning: Skipped corrupted game row (id: ${row['id']}): $e\n$stack');
      }
    }

    return games;
  }

  UnifiedGamePayload _rowToPayload(Map<String, dynamic> row) {
    List<NamedItem> parseJsonNamedList(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty) return [];
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          return decoded.whereType<Map>().map((e) => NamedItem(
            id: e['id']?.toString() ?? '',
            name: e['name']?.toString() ?? '',
          )).toList();
        }
      } catch (_) {}
      return [];
    }

    List<LinkItem> parseJsonLinkList(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty) return [];
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          return decoded.whereType<Map>().map((e) => LinkItem(
            name: e['name']?.toString() ?? '',
            url: e['url']?.toString() ?? '',
          )).toList();
        }
      } catch (_) {}
      return [];
    }

    Map<String, dynamic> parseJsonMap(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty) return {};
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
      return {};
    }

    return UnifiedGamePayload(
      id: row['id']?.toString() ?? '',
      gameId: row['game_id']?.toString() ?? '',
      pluginId: row['plugin_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      sortingName: row['sorting_name']?.toString() ?? row['name']?.toString() ?? '',
      description: row['description']?.toString(),
      notes: row['notes']?.toString(),
      playtimeSeconds: (row['playtime_seconds'] as num?)?.toInt() ?? 0,
      playCount: (row['play_count'] as num?)?.toInt() ?? 0,
      addedUtc: row['added_utc']?.toString(),
      modifiedUtc: row['modified_utc']?.toString(),
      lastActivityUtc: row['last_activity_utc']?.toString(),
      recentActivityUtc: row['recent_activity_utc']?.toString(),
      releaseDate: row['release_date']?.toString(),
      isInstalled: (row['is_installed'] as num?)?.toInt() == 1,
      installDirectory: row['install_directory']?.toString(),
      installSizeBytes: (row['install_size_bytes'] as num?)?.toInt(),
      hidden: (row['hidden'] as num?)?.toInt() == 1,
      isDuplicate: (row['is_duplicate'] as num?)?.toInt() == 1,
      otherCopies: (row['other_copies_json'] != null && row['other_copies_json'].toString().isNotEmpty)
          ? () {
              try {
                final list = jsonDecode(row['other_copies_json'].toString());
                if (list is List) {
                  return list.whereType<Map<String, dynamic>>().map((e) => DuplicateCopyPayload.fromJson(e)).toList();
                }
              } catch (_) {}
              return <DuplicateCopyPayload>[];
            }()
          : const [],
      favorite: (row['favorite'] as num?)?.toInt() == 1,
      userScore: (row['user_score'] as num?)?.toInt(),
      criticScore: (row['critic_score'] as num?)?.toInt(),
      communityScore: (row['community_score'] as num?)?.toInt(),
      version: row['version']?.toString(),
      source: (row['source_id'] != null || row['source_name'] != null)
          ? NamedItem(
              id: row['source_id']?.toString() ?? '',
              name: row['source_name']?.toString() ?? '',
            )
          : null,
      completionStatus: (row['completion_status_id'] != null || row['completion_status_name'] != null)
          ? NamedItem(
              id: row['completion_status_id']?.toString() ?? '',
              name: row['completion_status_name']?.toString() ?? '',
            )
          : null,
      platforms: parseJsonNamedList(row['platforms_json']?.toString()),
      genres: parseJsonNamedList(row['genres_json']?.toString()),
      categories: parseJsonNamedList(row['categories_json']?.toString()),
      tags: parseJsonNamedList(row['tags_json']?.toString()),
      developers: parseJsonNamedList(row['developers_json']?.toString()),
      publishers: parseJsonNamedList(row['publishers_json']?.toString()),
      features: parseJsonNamedList(row['features_json']?.toString()),
      links: parseJsonLinkList(row['links_json']?.toString()),
      media: MediaPayload(
        coverDriveFileId: row['cover_drive_file_id']?.toString(),
        coverSha256: row['cover_sha256']?.toString(),
        backgroundDriveFileId: row['background_drive_file_id']?.toString(),
        backgroundSha256: row['background_sha256']?.toString(),
        logoDriveFileId: row['logo_drive_file_id']?.toString(),
        microtrailerDriveFileId: row['microtrailer_drive_file_id']?.toString(),
        trailerDriveFileId: row['trailer_drive_file_id']?.toString(),
      ),
      addons: parseJsonMap(row['addons_json']?.toString()),
    );
  }
}
