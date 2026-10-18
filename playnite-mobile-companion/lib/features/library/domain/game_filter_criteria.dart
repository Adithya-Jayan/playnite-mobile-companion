import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';

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
  final bool showHiddenOnly;
  final int? minScore;
  final int? maxScore;
  final RatingScoreSource ratingScoreSource;

  // HowLongToBeat filters
  final int? hltbMinHours;
  final int? hltbMaxHours;

  // Diagnostic / Utility Filters
  final bool missingCoversOnly;
  final bool duplicateCopiesOnly;
  final bool missingMicrotrailersOnly;
  final bool unplayedOnly;

  bool get includeHidden => showHiddenOnly;

  const GameFilterCriteria({
    this.searchQuery = '',
    this.platforms = const {},
    this.sources = const {},
    this.genres = const {},
    this.tags = const {},
    this.completionStatuses = const {},
    this.isInstalled,
    this.isFavorite,
    bool? showHiddenOnly,
    bool? includeHidden,
    this.minScore,
    this.maxScore,
    this.ratingScoreSource = RatingScoreSource.community,
    this.hltbMinHours,
    this.hltbMaxHours,
    this.missingCoversOnly = false,
    this.duplicateCopiesOnly = false,
    this.missingMicrotrailersOnly = false,
    this.unplayedOnly = false,
  }) : showHiddenOnly = showHiddenOnly ?? includeHidden ?? false;

  bool get isEmpty =>
      searchQuery.trim().isEmpty &&
      platforms.isEmpty &&
      sources.isEmpty &&
      genres.isEmpty &&
      tags.isEmpty &&
      completionStatuses.isEmpty &&
      isInstalled == null &&
      isFavorite == null &&
      !showHiddenOnly &&
      (minScore == null || minScore == 0) &&
      (maxScore == null || maxScore == 100) &&
      (hltbMinHours == null || hltbMinHours == 0) &&
      (hltbMaxHours == null || hltbMaxHours == 0) &&
      !missingCoversOnly &&
      !duplicateCopiesOnly &&
      !missingMicrotrailersOnly &&
      !unplayedOnly;

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
    if (showHiddenOnly) count++;
    if ((minScore != null && minScore! > 0) || (maxScore != null && maxScore! < 100)) count++;
    if ((hltbMinHours != null && hltbMinHours! > 0) || (hltbMaxHours != null && hltbMaxHours! > 0)) count++;
    if (missingCoversOnly) count++;
    if (duplicateCopiesOnly) count++;
    if (missingMicrotrailersOnly) count++;
    if (unplayedOnly) count++;
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
    bool? showHiddenOnly,
    bool? includeHidden,
    int? minScore,
    int? maxScore,
    RatingScoreSource? ratingScoreSource,
    int? hltbMinHours,
    int? hltbMaxHours,
    bool? missingCoversOnly,
    bool? duplicateCopiesOnly,
    bool? missingMicrotrailersOnly,
    bool? unplayedOnly,
    bool clearInstalled = false,
    bool clearFavorite = false,
    bool clearScores = false,
    bool clearHltb = false,
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
      showHiddenOnly: showHiddenOnly ?? includeHidden ?? this.showHiddenOnly,
      minScore: clearScores ? null : (minScore ?? this.minScore),
      maxScore: clearScores ? null : (maxScore ?? this.maxScore),
      ratingScoreSource: ratingScoreSource ?? this.ratingScoreSource,
      hltbMinHours: clearHltb ? null : (hltbMinHours ?? this.hltbMinHours),
      hltbMaxHours: clearHltb ? null : (hltbMaxHours ?? this.hltbMaxHours),
      missingCoversOnly: missingCoversOnly ?? this.missingCoversOnly,
      duplicateCopiesOnly: duplicateCopiesOnly ?? this.duplicateCopiesOnly,
      missingMicrotrailersOnly: missingMicrotrailersOnly ?? this.missingMicrotrailersOnly,
      unplayedOnly: unplayedOnly ?? this.unplayedOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'searchQuery': searchQuery,
        'platforms': platforms.toList(),
        'sources': sources.toList(),
        'genres': genres.toList(),
        'tags': tags.toList(),
        'completionStatuses': completionStatuses.toList(),
        'isInstalled': isInstalled,
        'isFavorite': isFavorite,
        'showHiddenOnly': showHiddenOnly,
        'minScore': minScore,
        'maxScore': maxScore,
        'ratingScoreSource': ratingScoreSource.name,
        'hltbMinHours': hltbMinHours,
        'hltbMaxHours': hltbMaxHours,
        'missingCoversOnly': missingCoversOnly,
        'duplicateCopiesOnly': duplicateCopiesOnly,
        'missingMicrotrailersOnly': missingMicrotrailersOnly,
        'unplayedOnly': unplayedOnly,
      };

  factory GameFilterCriteria.fromJson(Map<String, dynamic> json) {
    final scoreSourceName = json['ratingScoreSource'] as String?;
    final scoreSource = RatingScoreSource.values.firstWhere(
      (e) => e.name == scoreSourceName,
      orElse: () => RatingScoreSource.community,
    );

    return GameFilterCriteria(
      searchQuery: json['searchQuery'] as String? ?? '',
      platforms: (json['platforms'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      genres: (json['genres'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      completionStatuses: (json['completionStatuses'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      isInstalled: json['isInstalled'] as bool?,
      isFavorite: json['isFavorite'] as bool?,
      showHiddenOnly: json['showHiddenOnly'] as bool? ?? false,
      minScore: (json['minScore'] as num?)?.toInt(),
      maxScore: (json['maxScore'] as num?)?.toInt(),
      ratingScoreSource: scoreSource,
      hltbMinHours: (json['hltbMinHours'] as num?)?.toInt(),
      hltbMaxHours: (json['hltbMaxHours'] as num?)?.toInt(),
      missingCoversOnly: json['missingCoversOnly'] as bool? ?? false,
      duplicateCopiesOnly: json['duplicateCopiesOnly'] as bool? ?? false,
      missingMicrotrailersOnly: json['missingMicrotrailersOnly'] as bool? ?? false,
      unplayedOnly: json['unplayedOnly'] as bool? ?? false,
    );
  }
}
