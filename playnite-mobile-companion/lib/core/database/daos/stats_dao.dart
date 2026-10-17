import 'dart:convert';
import '../app_database.dart';

class TopPlayedGameEntry {
  final String id;
  final String name;
  final int playtimeSeconds;
  final String? coverDriveFileId;

  const TopPlayedGameEntry({
    required this.id,
    required this.name,
    required this.playtimeSeconds,
    this.coverDriveFileId,
  });
}

class RecentSessionEntry {
  final String gameId;
  final String gameName;
  final String dateSessionUtc;
  final int elapsedSeconds;

  const RecentSessionEntry({
    required this.gameId,
    required this.gameName,
    required this.dateSessionUtc,
    required this.elapsedSeconds,
  });
}

class LibraryStats {
  final int totalGames;
  final int totalPlaytimeSeconds;
  final int installedCount;
  final int favoritesCount;
  final Map<String, int> playtimeBySource;
  final Map<String, int> playtimeByPlatform;
  final Map<String, int> completionBreakdown;
  final List<TopPlayedGameEntry> topPlayedGames;
  final List<RecentSessionEntry> recentSessions;

  const LibraryStats({
    this.totalGames = 0,
    this.totalPlaytimeSeconds = 0,
    this.installedCount = 0,
    this.favoritesCount = 0,
    this.playtimeBySource = const {},
    this.playtimeByPlatform = const {},
    this.completionBreakdown = const {},
    this.topPlayedGames = const [],
    this.recentSessions = const [],
  });
}

class StatsDao {
  final AppDatabase database;

  StatsDao(this.database);

  Future<LibraryStats> calculateLibraryStats() async {
    final db = database.db;

    // 1. High level counters
    final countResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_games,
        COALESCE(SUM(playtime_seconds), 0) as total_playtime,
        COALESCE(SUM(is_installed), 0) as installed_count,
        COALESCE(SUM(favorite), 0) as favorite_count
      FROM games;
    ''');

    final firstRow = countResult.isNotEmpty ? countResult.first : <String, dynamic>{};
    final totalGames = (firstRow['total_games'] as num?)?.toInt() ?? 0;
    final totalPlaytime = (firstRow['total_playtime'] as num?)?.toInt() ?? 0;
    final installedCount = (firstRow['installed_count'] as num?)?.toInt() ?? 0;
    final favoritesCount = (firstRow['favorite_count'] as num?)?.toInt() ?? 0;

    // 2. Playtime by Source
    final sourceRows = await db.rawQuery('''
      SELECT 
        COALESCE(source_name, 'Unknown') as source_name,
        SUM(playtime_seconds) as total_seconds
      FROM games
      GROUP BY source_name
      ORDER BY total_seconds DESC;
    ''');
    final playtimeBySource = <String, int>{};
    for (final r in sourceRows) {
      final name = r['source_name'] as String;
      final seconds = (r['total_seconds'] as num?)?.toInt() ?? 0;
      if (seconds > 0) playtimeBySource[name] = seconds;
    }

    // 3. Completion Breakdown
    final completionRows = await db.rawQuery('''
      SELECT 
        COALESCE(completion_status_name, 'Not Set') as status_name,
        COUNT(*) as count
      FROM games
      GROUP BY completion_status_name
      ORDER BY count DESC;
    ''');
    final completionBreakdown = <String, int>{};
    for (final r in completionRows) {
      final name = r['status_name'] as String;
      final count = (r['count'] as num?)?.toInt() ?? 0;
      completionBreakdown[name] = count;
    }

    // 4. Playtime by Platform (aggregating across JSON platform lists)
    final platformRows = await db.rawQuery(
      'SELECT platforms_json, playtime_seconds FROM games WHERE playtime_seconds > 0;',
    );
    final playtimeByPlatform = <String, int>{};
    for (final r in platformRows) {
      final jsonStr = r['platforms_json'] as String?;
      final playtime = (r['playtime_seconds'] as num?)?.toInt() ?? 0;
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final list = jsonDecode(jsonStr);
          if (list is List && list.isNotEmpty) {
            for (final p in list) {
              if (p is Map && p['name'] != null) {
                final platName = p['name'] as String;
                playtimeByPlatform[platName] = (playtimeByPlatform[platName] ?? 0) + playtime;
              }
            }
          }
        } catch (_) {}
      }
    }

    // 5. Top Played Games
    final topRows = await db.rawQuery('''
      SELECT id, name, playtime_seconds, cover_drive_file_id
      FROM games
      WHERE playtime_seconds > 0
      ORDER BY playtime_seconds DESC
      LIMIT 10;
    ''');
    final topPlayed = topRows.map((r) => TopPlayedGameEntry(
      id: r['id'] as String,
      name: r['name'] as String,
      playtimeSeconds: (r['playtime_seconds'] as num).toInt(),
      coverDriveFileId: r['cover_drive_file_id'] as String?,
    )).toList();

    // 6. Recent Sessions
    final sessionRows = await db.rawQuery('''
      SELECT 
        ps.game_id,
        g.name as game_name,
        ps.date_session_utc,
        ps.elapsed_seconds
      FROM play_sessions ps
      JOIN games g ON ps.game_id = g.id
      ORDER BY ps.date_session_utc DESC
      LIMIT 15;
    ''');
    final recentSessions = sessionRows.map((r) => RecentSessionEntry(
      gameId: r['game_id'] as String,
      gameName: r['game_name'] as String? ?? 'Unknown',
      dateSessionUtc: r['date_session_utc'] as String,
      elapsedSeconds: (r['elapsed_seconds'] as num).toInt(),
    )).toList();

    return LibraryStats(
      totalGames: totalGames,
      totalPlaytimeSeconds: totalPlaytime,
      installedCount: installedCount,
      favoritesCount: favoritesCount,
      playtimeBySource: playtimeBySource,
      playtimeByPlatform: playtimeByPlatform,
      completionBreakdown: completionBreakdown,
      topPlayedGames: topPlayed,
      recentSessions: recentSessions,
    );
  }
}
