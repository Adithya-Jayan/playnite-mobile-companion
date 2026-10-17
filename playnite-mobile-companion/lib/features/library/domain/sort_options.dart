enum SortField {
  title,
  playtime,
  lastPlayed,
  userScore,
  criticScore,
  releaseDate,
  addedDate,
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
  static const scoreDesc = SortOption(field: SortField.userScore, direction: SortDirection.descending);
  static const releaseDesc = SortOption(field: SortField.releaseDate, direction: SortDirection.descending);

  String get label {
    switch (field) {
      case SortField.title:
        return direction == SortDirection.ascending ? 'Title (A-Z)' : 'Title (Z-A)';
      case SortField.playtime:
        return 'Playtime (High to Low)';
      case SortField.lastPlayed:
        return 'Recently Played';
      case SortField.userScore:
        return 'User Score';
      case SortField.criticScore:
        return 'Critic Score';
      case SortField.releaseDate:
        return 'Release Date';
      case SortField.addedDate:
        return 'Recently Added';
    }
  }

  String toSqlOrderBy() {
    final dir = direction == SortDirection.ascending ? 'ASC' : 'DESC';
    switch (field) {
      case SortField.title:
        return 'sorting_name COLLATE NOCASE $dir';
      case SortField.playtime:
        return 'playtime_seconds $dir';
      case SortField.lastPlayed:
        return 'last_activity_utc $dir';
      case SortField.userScore:
        return 'user_score $dir';
      case SortField.criticScore:
        return 'critic_score $dir';
      case SortField.releaseDate:
        return 'release_date $dir';
      case SortField.addedDate:
        return 'added_utc $dir';
    }
  }
}
