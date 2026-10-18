import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';

/// Triage and diagnostic utility filter modes.
/// Mutually exclusive lenses for auditing specific subsets of the library.
enum UtilityFilterMode {
  none,                // Normal library browsing
  onlyHidden,          // Show only manually hidden items
  onlyDuplicates,      // Show only DuplicateHider duplicate copies
  onlyUnplayed,        // Show only unplayed games (0 hours / 0 sessions)
  missingCovers,       // Show only games missing cover art
  missingMicrotrailers,// Show only games missing microtrailers
}

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
  final int? minScore;
  final int? maxScore;
  final RatingScoreSource ratingScoreSource;

  // HowLongToBeat filters
  final int? hltbMinHours;
  final int? hltbMaxHours;

  // Gallery baseline inclusion flags (from GallerySettings)
  final bool includeUserHidden;
  final bool includeDuplicateHider;

  // Single-select Diagnostic / Utility Filter Mode
  final UtilityFilterMode utilityMode;

  // Backwards-compatible convenience getters
  bool get showHiddenOnly => utilityMode == UtilityFilterMode.onlyHidden;
  bool get duplicateCopiesOnly => utilityMode == UtilityFilterMode.onlyDuplicates;
  bool get unplayedOnly => utilityMode == UtilityFilterMode.onlyUnplayed;
  bool get missingCoversOnly => utilityMode == UtilityFilterMode.missingCovers;
  bool get missingMicrotrailersOnly => utilityMode == UtilityFilterMode.missingMicrotrailers;
  bool get includeHidden => showHiddenOnly || includeUserHidden || includeDuplicateHider;

  const GameFilterCriteria({
    this.searchQuery = '',
    this.platforms = const {},
    this.sources = const {},
    this.genres = const {},
    this.tags = const {},
    this.completionStatuses = const {},
    this.isInstalled,
    this.isFavorite,
    this.minScore,
    this.maxScore,
    this.ratingScoreSource = RatingScoreSource.community,
    this.hltbMinHours,
    this.hltbMaxHours,
    this.includeUserHidden = false,
    this.includeDuplicateHider = false,
    UtilityFilterMode? utilityMode,
    bool? showHiddenOnly,
    bool? includeHidden,
    bool? missingCoversOnly,
    bool? duplicateCopiesOnly,
    bool? missingMicrotrailersOnly,
    bool? unplayedOnly,
  }) : utilityMode = utilityMode ??
            ((showHiddenOnly == true || includeHidden == true)
                ? UtilityFilterMode.onlyHidden
                : (duplicateCopiesOnly == true
                    ? UtilityFilterMode.onlyDuplicates
                    : (unplayedOnly == true
                        ? UtilityFilterMode.onlyUnplayed
                        : (missingCoversOnly == true
                            ? UtilityFilterMode.missingCovers
                            : (missingMicrotrailersOnly == true
                                ? UtilityFilterMode.missingMicrotrailers
                                : UtilityFilterMode.none)))));

  bool get isEmpty =>
      searchQuery.trim().isEmpty &&
      platforms.isEmpty &&
      sources.isEmpty &&
      genres.isEmpty &&
      tags.isEmpty &&
      completionStatuses.isEmpty &&
      isInstalled == null &&
      isFavorite == null &&
      utilityMode == UtilityFilterMode.none &&
      (minScore == null || minScore == 0) &&
      (maxScore == null || maxScore == 100) &&
      (hltbMinHours == null || hltbMinHours == 0) &&
      (hltbMaxHours == null || hltbMaxHours == 0);

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
    if (utilityMode != UtilityFilterMode.none) count++;
    if ((minScore != null && minScore! > 0) || (maxScore != null && maxScore! < 100)) count++;
    if ((hltbMinHours != null && hltbMinHours! > 0) || (hltbMaxHours != null && hltbMaxHours! > 0)) count++;
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
    int? minScore,
    int? maxScore,
    RatingScoreSource? ratingScoreSource,
    int? hltbMinHours,
    int? hltbMaxHours,
    bool? includeUserHidden,
    bool? includeDuplicateHider,
    UtilityFilterMode? utilityMode,
    bool? showHiddenOnly,
    bool? includeHidden,
    bool? missingCoversOnly,
    bool? duplicateCopiesOnly,
    bool? missingMicrotrailersOnly,
    bool? unplayedOnly,
    bool clearInstalled = false,
    bool clearFavorite = false,
    bool clearScores = false,
    bool clearHltb = false,
    bool clearUtility = false,
  }) {
    UtilityFilterMode resolvedUtility;
    if (clearUtility) {
      resolvedUtility = UtilityFilterMode.none;
    } else if (utilityMode != null) {
      resolvedUtility = utilityMode;
    } else if (showHiddenOnly != null || includeHidden != null) {
      resolvedUtility = (showHiddenOnly == true || includeHidden == true)
          ? UtilityFilterMode.onlyHidden
          : (this.utilityMode == UtilityFilterMode.onlyHidden ? UtilityFilterMode.none : this.utilityMode);
    } else if (duplicateCopiesOnly != null) {
      resolvedUtility = duplicateCopiesOnly
          ? UtilityFilterMode.onlyDuplicates
          : (this.utilityMode == UtilityFilterMode.onlyDuplicates ? UtilityFilterMode.none : this.utilityMode);
    } else if (unplayedOnly != null) {
      resolvedUtility = unplayedOnly
          ? UtilityFilterMode.onlyUnplayed
          : (this.utilityMode == UtilityFilterMode.onlyUnplayed ? UtilityFilterMode.none : this.utilityMode);
    } else if (missingCoversOnly != null) {
      resolvedUtility = missingCoversOnly
          ? UtilityFilterMode.missingCovers
          : (this.utilityMode == UtilityFilterMode.missingCovers ? UtilityFilterMode.none : this.utilityMode);
    } else if (missingMicrotrailersOnly != null) {
      resolvedUtility = missingMicrotrailersOnly
          ? UtilityFilterMode.missingMicrotrailers
          : (this.utilityMode == UtilityFilterMode.missingMicrotrailers ? UtilityFilterMode.none : this.utilityMode);
    } else {
      resolvedUtility = this.utilityMode;
    }

    return GameFilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      platforms: platforms ?? this.platforms,
      sources: sources ?? this.sources,
      genres: genres ?? this.genres,
      tags: tags ?? this.tags,
      completionStatuses: completionStatuses ?? this.completionStatuses,
      isInstalled: clearInstalled ? null : (isInstalled ?? this.isInstalled),
      isFavorite: clearFavorite ? null : (isFavorite ?? this.isFavorite),
      minScore: clearScores ? null : (minScore ?? this.minScore),
      maxScore: clearScores ? null : (maxScore ?? this.maxScore),
      ratingScoreSource: ratingScoreSource ?? this.ratingScoreSource,
      hltbMinHours: clearHltb ? null : (hltbMinHours ?? this.hltbMinHours),
      hltbMaxHours: clearHltb ? null : (hltbMaxHours ?? this.hltbMaxHours),
      includeUserHidden: includeUserHidden ?? this.includeUserHidden,
      includeDuplicateHider: includeDuplicateHider ?? this.includeDuplicateHider,
      utilityMode: resolvedUtility,
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
        'utilityMode': utilityMode.name,
        'includeUserHidden': includeUserHidden,
        'includeDuplicateHider': includeDuplicateHider,
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

    UtilityFilterMode resolvedMode = UtilityFilterMode.none;
    if (json['utilityMode'] is String) {
      final modeStr = json['utilityMode'] as String;
      resolvedMode = UtilityFilterMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => UtilityFilterMode.none,
      );
    } else {
      if (json['showHiddenOnly'] as bool? ?? false) {
        resolvedMode = UtilityFilterMode.onlyHidden;
      } else if (json['duplicateCopiesOnly'] as bool? ?? false) {
        resolvedMode = UtilityFilterMode.onlyDuplicates;
      } else if (json['unplayedOnly'] as bool? ?? false) {
        resolvedMode = UtilityFilterMode.onlyUnplayed;
      } else if (json['missingCoversOnly'] as bool? ?? false) {
        resolvedMode = UtilityFilterMode.missingCovers;
      } else if (json['missingMicrotrailersOnly'] as bool? ?? false) {
        resolvedMode = UtilityFilterMode.missingMicrotrailers;
      }
    }

    return GameFilterCriteria(
      searchQuery: json['searchQuery'] as String? ?? '',
      platforms: (json['platforms'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      genres: (json['genres'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      completionStatuses: (json['completionStatuses'] as List?)?.map((e) => e.toString()).toSet() ?? const {},
      isInstalled: json['isInstalled'] as bool?,
      isFavorite: json['isFavorite'] as bool?,
      includeUserHidden: json['includeUserHidden'] as bool? ?? false,
      includeDuplicateHider: json['includeDuplicateHider'] as bool? ?? false,
      utilityMode: resolvedMode,
      minScore: (json['minScore'] as num?)?.toInt(),
      maxScore: (json['maxScore'] as num?)?.toInt(),
      ratingScoreSource: scoreSource,
      hltbMinHours: (json['hltbMinHours'] as num?)?.toInt(),
      hltbMaxHours: (json['hltbMaxHours'] as num?)?.toInt(),
    );
  }
}
