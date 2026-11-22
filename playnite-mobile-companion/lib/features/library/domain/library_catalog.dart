import 'dart:async';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

/// Single unified interface for high-performance catalog search, filtering,
/// pagination, and reactive live streaming.
abstract class ILibraryCatalog {
  /// Queries games matching [criteria] and [sort], with optional pagination [limit] and [offset].
  Future<List<UnifiedGamePayload>> getGames({
    required GameFilterCriteria criteria,
    required SortOption sort,
    int? limit,
    int? offset,
  });

  /// Returns count of games matching [criteria], or total games count if [criteria] is null.
  Future<int> getGamesCount({
    GameFilterCriteria? criteria,
  });

  /// Broadcast stream emitting updated game lists whenever the library changes.
  Stream<List<UnifiedGamePayload>> watchGames({
    required GameFilterCriteria criteria,
    required SortOption sort,
    int? limit,
    int? offset,
  });

  /// Broadcast stream emitting updated counts whenever the library changes.
  Stream<int> watchGamesCount({
    required GameFilterCriteria criteria,
  });

  /// Notifies active subscribers that underlying library data has mutated.
  void notifyChanged();
}

/// Canonical production implementation of [ILibraryCatalog] backed by SQLite.
class LibraryCatalog implements ILibraryCatalog {
  final GameDao _gameDao;

  LibraryCatalog(AppDatabase database) : _gameDao = GameDao(database);
  LibraryCatalog.withDao(this._gameDao);

  @override
  Future<List<UnifiedGamePayload>> getGames({
    required GameFilterCriteria criteria,
    required SortOption sort,
    int? limit,
    int? offset,
  }) {
    return _gameDao.getFilteredGames(
      criteria: criteria,
      sort: sort,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> getGamesCount({GameFilterCriteria? criteria}) {
    return _gameDao.getGamesCount(criteria: criteria);
  }

  @override
  Stream<List<UnifiedGamePayload>> watchGames({
    required GameFilterCriteria criteria,
    required SortOption sort,
    int? limit,
    int? offset,
  }) {
    return _gameDao.watchGames(
      criteria: criteria,
      sort: sort,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Stream<int> watchGamesCount({required GameFilterCriteria criteria}) {
    return _gameDao.watchGamesCount(criteria: criteria);
  }

  @override
  void notifyChanged() {
    _gameDao.notifyChanged();
  }
}
