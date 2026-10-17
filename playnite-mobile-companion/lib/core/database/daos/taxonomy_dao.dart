import 'dart:convert';
import 'package:playnite_mobile_companion/core/database/app_database.dart';

class FilterTaxonomies {
  final List<String> platforms;
  final List<String> sources;
  final List<String> genres;
  final List<String> tags;
  final List<String> completionStatuses;

  const FilterTaxonomies({
    this.platforms = const [],
    this.sources = const [],
    this.genres = const [],
    this.tags = const [],
    this.completionStatuses = const [],
  });
}

class TaxonomyDao {
  final AppDatabase database;

  TaxonomyDao(this.database);

  Future<FilterTaxonomies> getAvailableTaxonomies() async {
    final db = database.db;

    // Sources
    final sourceRows = await db.rawQuery(
      "SELECT DISTINCT source_name FROM games WHERE source_name IS NOT NULL AND source_name != '' ORDER BY source_name ASC;",
    );
    final sources = sourceRows.map((r) => r['source_name'] as String).toList();

    // Completion Statuses
    final statusRows = await db.rawQuery(
      "SELECT DISTINCT completion_status_name FROM games WHERE completion_status_name IS NOT NULL AND completion_status_name != '' ORDER BY completion_status_name ASC;",
    );
    final completionStatuses = statusRows.map((r) => r['completion_status_name'] as String).toList();

    // Platforms, Genres, Tags extracted from JSON columns
    final platformSet = <String>{};
    final genreSet = <String>{};
    final tagSet = <String>{};

    final jsonRows = await db.query(
      'games',
      columns: ['platforms_json', 'genres_json', 'tags_json'],
    );

    for (final row in jsonRows) {
      _extractNames(row['platforms_json'] as String?, platformSet);
      _extractNames(row['genres_json'] as String?, genreSet);
      _extractNames(row['tags_json'] as String?, tagSet);
    }

    final platforms = platformSet.toList()..sort();
    final genres = genreSet.toList()..sort();
    final tags = tagSet.toList()..sort();

    return FilterTaxonomies(
      platforms: platforms,
      sources: sources,
      genres: genres,
      tags: tags,
      completionStatuses: completionStatuses,
    );
  }

  void _extractNames(String? jsonStr, Set<String> targetSet) {
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final list = jsonDecode(jsonStr);
      if (list is List) {
        for (final item in list) {
          if (item is Map && item['name'] != null && (item['name'] as String).isNotEmpty) {
            targetSet.add(item['name'] as String);
          }
        }
      }
    } catch (_) {}
  }
}
