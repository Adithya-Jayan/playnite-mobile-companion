import 'dart:math';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

enum SearchTier implements Comparable<SearchTier> {
  tier1Exact(1),
  tier1Prefix(2),
  tier1WordPrefix(3),
  tier1Substring(4),
  tier2Fuzzy(5),
  tier3Metadata(6);

  final int rank;
  const SearchTier(this.rank);

  @override
  int compareTo(SearchTier other) => rank.compareTo(other.rank);
}

class SearchMatchResult {
  final SearchTier tier;
  final double score;

  const SearchMatchResult(this.tier, this.score);
}

/// Two-Tier Fuzzy Search Engine for Playnite Mobile Companion.
///
/// Implements three-tier search ranking:
/// - Tier 1: Exact and prefix matches on game title (`name`, `sortingName`).
/// - Tier 2: Typo-tolerant / fuzzy matches on game title (Levenshtein distance within threshold).
/// - Tier 3: Metadata matches (developers, publishers, genres, tags, description).
class FuzzySearchEngine {
  /// Computes classic Levenshtein edit distance between strings [s] and [t].
  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final sLower = s.toLowerCase();
    final tLower = t.toLowerCase();

    final List<int> v0 = List<int>.generate(tLower.length + 1, (i) => i);
    final List<int> v1 = List<int>.filled(tLower.length + 1, 0);

    for (int i = 0; i < sLower.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < tLower.length; j++) {
        final cost = (sLower.codeUnitAt(i) == tLower.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= tLower.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v0[tLower.length];
  }

  /// Determines the maximum allowed Levenshtein edit distance based on query length.
  static int allowedEdits(int queryLength) {
    if (queryLength <= 2) return 0;
    if (queryLength <= 5) return 1;
    if (queryLength <= 11) return 2;
    return 3;
  }

  /// Evaluates [game] against [rawQuery], returning a [SearchMatchResult] if it matches.
  static SearchMatchResult? rankGame(UnifiedGamePayload game, String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return const SearchMatchResult(SearchTier.tier1Exact, 0.0);
    }

    final nameLower = game.name.trim().toLowerCase();
    final sortLower = game.sortingName.trim().toLowerCase();

    // ---------------------------------------------------------
    // Tier 1: Exact and Prefix Title Matches
    // ---------------------------------------------------------
    if (nameLower == q || sortLower == q) {
      return const SearchMatchResult(SearchTier.tier1Exact, 1.0);
    }

    if (nameLower.startsWith(q) || sortLower.startsWith(q)) {
      final lenDiff = (nameLower.length - q.length).clamp(0, 100);
      return SearchMatchResult(SearchTier.tier1Prefix, 1.1 + (lenDiff * 0.001));
    }

    // Tokenized word matching in title
    final titleWords = nameLower
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    for (final word in titleWords) {
      if (word == q) {
        return const SearchMatchResult(SearchTier.tier1WordPrefix, 1.2);
      }
      if (word.startsWith(q)) {
        return const SearchMatchResult(SearchTier.tier1WordPrefix, 1.25);
      }
    }

    // Multi-word token matching in title (e.g. "witcher wild hunt" in "The Witcher 3: Wild Hunt")
    final queryWords = q
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (queryWords.length > 1) {
      final allWordsMatch = queryWords.every((qw) => titleWords.any((tw) => tw.startsWith(qw)));
      if (allWordsMatch) {
        return const SearchMatchResult(SearchTier.tier1WordPrefix, 1.28);
      }
    }

    if (nameLower.contains(q) || (sortLower.isNotEmpty && sortLower.contains(q))) {
      return const SearchMatchResult(SearchTier.tier1Substring, 1.3);
    }

    // ---------------------------------------------------------
    // Tier 2: Typo-Tolerant / Fuzzy Title Matches
    // ---------------------------------------------------------
    final maxEdits = allowedEdits(q.length);
    if (maxEdits > 0) {
      // 1. Check whole title
      if ((nameLower.length - q.length).abs() <= maxEdits) {
        final d = levenshtein(q, nameLower);
        if (d <= maxEdits) {
          return SearchMatchResult(SearchTier.tier2Fuzzy, 2.0 + (d / q.length));
        }
      }

      // 2. Check each word in title
      int? bestWordDist;
      for (final word in titleWords) {
        if ((word.length - q.length).abs() <= maxEdits) {
          final d = levenshtein(q, word);
          if (d <= maxEdits) {
            if (bestWordDist == null || d < bestWordDist) {
              bestWordDist = d;
            }
          }
        }
      }
      if (bestWordDist != null) {
        return SearchMatchResult(SearchTier.tier2Fuzzy, 2.1 + (bestWordDist / q.length));
      }
    }

    // ---------------------------------------------------------
    // Tier 3: Metadata Matches (Developers, Publishers, Genres, Tags, Description)
    // ---------------------------------------------------------
    for (final dev in game.developers) {
      if (dev.name.toLowerCase().contains(q)) {
        return const SearchMatchResult(SearchTier.tier3Metadata, 3.0);
      }
    }

    for (final pub in game.publishers) {
      if (pub.name.toLowerCase().contains(q)) {
        return const SearchMatchResult(SearchTier.tier3Metadata, 3.05);
      }
    }

    for (final gen in game.genres) {
      if (gen.name.toLowerCase().contains(q)) {
        return const SearchMatchResult(SearchTier.tier3Metadata, 3.1);
      }
    }

    for (final tag in game.tags) {
      if (tag.name.toLowerCase().contains(q)) {
        return const SearchMatchResult(SearchTier.tier3Metadata, 3.2);
      }
    }

    if (game.description != null && game.description!.isNotEmpty) {
      if (game.description!.toLowerCase().contains(q)) {
        return const SearchMatchResult(SearchTier.tier3Metadata, 3.5);
      }
    }

    return null;
  }

  /// Filters [games] by [query] and sorts results according to the three-tier hierarchy.
  static List<UnifiedGamePayload> filterAndRank(
    List<UnifiedGamePayload> games,
    String query, {
    SortOption? baseSort,
  }) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return List.of(games);

    final matches = <({UnifiedGamePayload game, SearchMatchResult result})>[];
    for (final game in games) {
      final res = rankGame(game, cleanQuery);
      if (res != null) {
        matches.add((game: game, result: res));
      }
    }

    matches.sort((a, b) {
      final tierCmp = a.result.tier.compareTo(b.result.tier);
      if (tierCmp != 0) return tierCmp;

      final scoreCmp = a.result.score.compareTo(b.result.score);
      if (scoreCmp != 0) return scoreCmp;

      // Tie-breaker: sort according to requested baseSort
      if (baseSort != null) {
        return _compareGamesBySort(a.game, b.game, baseSort);
      }
      return a.game.sortingName.compareTo(b.game.sortingName);
    });

    return matches.map((m) => m.game).toList();
  }

  static int _compareGamesBySort(UnifiedGamePayload a, UnifiedGamePayload b, SortOption sort) {
    switch (sort.field) {
      case SortField.title:
        final cmp = (a.sortingName.isNotEmpty ? a.sortingName : a.name)
            .compareTo(b.sortingName.isNotEmpty ? b.sortingName : b.name);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.playtime:
        final cmp = a.playtimeSeconds.compareTo(b.playtimeSeconds);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.lastPlayed:
        final aAct = a.lastActivityUtc ?? '';
        final bAct = b.lastActivityUtc ?? '';
        final cmp = aAct.compareTo(bAct);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.releaseDate:
        final aRel = a.releaseDate ?? '';
        final bRel = b.releaseDate ?? '';
        final cmp = aRel.compareTo(bRel);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.addedDate:
        final aAdd = a.addedUtc ?? '';
        final bAdd = b.addedUtc ?? '';
        final cmp = aAdd.compareTo(bAdd);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.timesPlayed:
        final cmp = a.playCount.compareTo(b.playCount);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.userScore:
        final aScore = a.userScore ?? -1;
        final bScore = b.userScore ?? -1;
        final cmp = aScore.compareTo(bScore);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.criticScore:
        final aScore = a.criticScore ?? -1;
        final bScore = b.criticScore ?? -1;
        final cmp = aScore.compareTo(bScore);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.communityScore:
        final aScore = a.communityScore ?? -1;
        final bScore = b.communityScore ?? -1;
        final cmp = aScore.compareTo(bScore);
        return sort.direction == SortDirection.ascending ? cmp : -cmp;

      case SortField.random:
        return 0;
    }
  }
}
