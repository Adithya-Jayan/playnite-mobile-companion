enum SortField {
  title,          // sorting_name COLLATE NOCASE
  addedDate,      // added_utc
  playtime,       // playtime_seconds
  lastPlayed,     // last_activity_utc
  timesPlayed,    // play_count
  communityScore, // community_score
  criticScore,    // critic_score
  releaseDate,    // release_date
  userScore,      // user_score
}

enum SortDirection {
  ascending,
  descending,
}

class SortOption {
  final SortField field;
  final SortDirection direction;

  const SortOption({
    required this.field,
    this.direction = SortDirection.ascending,
  });

  static const titleAsc = SortOption(field: SortField.title, direction: SortDirection.ascending);
  static const titleDesc = SortOption(field: SortField.title, direction: SortDirection.descending);
  static const playtimeDesc = SortOption(field: SortField.playtime, direction: SortDirection.descending);
  static const lastPlayedDesc = SortOption(field: SortField.lastPlayed, direction: SortDirection.descending);
  static const communityScoreDesc = SortOption(field: SortField.communityScore, direction: SortDirection.descending);
  static const criticScoreDesc = SortOption(field: SortField.criticScore, direction: SortDirection.descending);
  static const releaseDesc = SortOption(field: SortField.releaseDate, direction: SortDirection.descending);
  static const addedDesc = SortOption(field: SortField.addedDate, direction: SortDirection.descending);
  static const scoreDesc = SortOption(field: SortField.userScore, direction: SortDirection.descending);

  String get label {
    switch (field) {
      case SortField.title:
        return direction == SortDirection.ascending ? 'Title (A-Z)' : 'Title (Z-A)';
      case SortField.addedDate:
        return direction == SortDirection.descending ? 'Recently Added' : 'Oldest Added';
      case SortField.playtime:
        return direction == SortDirection.descending ? 'Playtime (High to Low)' : 'Playtime (Low to High)';
      case SortField.lastPlayed:
        return direction == SortDirection.descending ? 'Recently Played' : 'Least Recently Played';
      case SortField.timesPlayed:
        return direction == SortDirection.descending ? 'Play Count (High to Low)' : 'Play Count (Low to High)';
      case SortField.communityScore:
        return direction == SortDirection.descending ? 'Community Score (High to Low)' : 'Community Score (Low to High)';
      case SortField.criticScore:
        return direction == SortDirection.descending ? 'Critic Score (High to Low)' : 'Critic Score (Low to High)';
      case SortField.releaseDate:
        return direction == SortDirection.descending ? 'Release Date (Newest)' : 'Release Date (Oldest)';
      case SortField.userScore:
        return direction == SortDirection.descending ? 'User Score (High to Low)' : 'User Score (Low to High)';
    }
  }

  String toSqlOrderBy() {
    final dir = direction == SortDirection.ascending ? 'ASC' : 'DESC';
    switch (field) {
      case SortField.title:
        return 'sorting_name COLLATE NOCASE $dir';
      case SortField.addedDate:
        return 'added_utc $dir';
      case SortField.playtime:
        return 'playtime_seconds $dir';
      case SortField.lastPlayed:
        return 'last_activity_utc $dir';
      case SortField.timesPlayed:
        return 'play_count $dir';
      case SortField.communityScore:
        return 'community_score $dir';
      case SortField.criticScore:
        return 'critic_score $dir';
      case SortField.releaseDate:
        return 'release_date $dir';
      case SortField.userScore:
        return 'user_score $dir';
    }
  }
}
