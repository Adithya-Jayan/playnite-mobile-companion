/// Multi-criteria filter options for library browsing.
class GameFilterCriteria {
  final String searchQuery;
  final Set<String> platforms;
  final Set<String> sources;
  final Set<String> genres;
  final Set<String> tags;
  final Set<String> completionStatuses;
  final bool? isInstalled;
  final bool? isFavorite;
  final bool includeHidden;
  final int? minScore;
  final int? maxScore;

  const GameFilterCriteria({
    this.searchQuery = '',
    this.platforms = const {},
    this.sources = const {},
    this.genres = const {},
    this.tags = const {},
    this.completionStatuses = const {},
    this.isInstalled,
    this.isFavorite,
    this.includeHidden = false,
    this.minScore,
    this.maxScore,
  });

  bool get isEmpty =>
      searchQuery.trim().isEmpty &&
      platforms.isEmpty &&
      sources.isEmpty &&
      genres.isEmpty &&
      tags.isEmpty &&
      completionStatuses.isEmpty &&
      isInstalled == null &&
      isFavorite == null &&
      !includeHidden &&
      minScore == null &&
      maxScore == null;

  int get activeFiltersCount {
    var count = 0;
    if (searchQuery.trim().isNotEmpty) count++;
    count += platforms.length;
    count += sources.length;
    count += genres.length;
    count += tags.length;
    count += completionStatuses.length;
    if (isInstalled != null) count++;
    if (isFavorite != null) count++;
    if (includeHidden) count++;
    if (minScore != null || maxScore != null) count++;
    return count;
  }

  GameFilterCriteria copyWith({
    String? searchQuery,
    Set<String>? platforms,
    Set<String>? sources,
    Set<String>? genres,
    Set<String>? tags,
    Set<String>? completionStatuses,
    bool? isInstalled,
    bool? isFavorite,
    bool? includeHidden,
    int? minScore,
    int? maxScore,
    bool clearInstalled = false,
    bool clearFavorite = false,
    bool clearScores = false,
  }) {
    return GameFilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      platforms: platforms ?? this.platforms,
      sources: sources ?? this.sources,
      genres: genres ?? this.genres,
      tags: tags ?? this.tags,
      completionStatuses: completionStatuses ?? this.completionStatuses,
      isInstalled: clearInstalled ? null : (isInstalled ?? this.isInstalled),
      isFavorite: clearFavorite ? null : (isFavorite ?? this.isFavorite),
      includeHidden: includeHidden ?? this.includeHidden,
      minScore: clearScores ? null : (minScore ?? this.minScore),
      maxScore: clearScores ? null : (maxScore ?? this.maxScore),
    );
  }
}
