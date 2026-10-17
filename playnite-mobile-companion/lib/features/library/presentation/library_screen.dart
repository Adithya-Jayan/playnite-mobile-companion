import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/stats/presentation/stats_dashboard_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/widgets/sync_dialog.dart';
import 'widgets/filter_drawer.dart';
import 'widgets/game_card_grid.dart';
import 'widgets/game_details_tile.dart';
import 'widgets/game_list_tile.dart';
import 'widgets/library_search_bar.dart';

enum ViewMode { grid, list, details }

class LibraryScreen extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback? onTriggerSync;

  const LibraryScreen({
    super.key,
    required this.database,
    this.onTriggerSync,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final GameDao _gameDao;
  late final TaxonomyDao _taxonomyDao;

  List<UnifiedGamePayload> _games = [];
  int _totalGamesCount = 0;
  FilterTaxonomies _taxonomies = const FilterTaxonomies();
  bool _isLoading = true;
  String? _loadError;

  ViewMode _viewMode = ViewMode.grid;
  SortOption _sortOption = SortOption.titleAsc;
  GameFilterCriteria _filterCriteria = const GameFilterCriteria();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _gameDao = GameDao(widget.database);
    _taxonomyDao = TaxonomyDao(widget.database);
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final totalCount = await _gameDao.getGamesCount();
      final taxonomies = await _taxonomyDao.getAvailableTaxonomies();
      final games = await _gameDao.getFilteredGames(
        criteria: _filterCriteria,
        sort: _sortOption,
      );

      if (mounted) {
        setState(() {
          _games = games;
          _taxonomies = taxonomies;
          _totalGamesCount = totalCount;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading games: $e\n$stack');
      final totalCount = await _gameDao.getGamesCount().catchError((_) => 0);
      if (mounted) {
        setState(() {
          _totalGamesCount = totalCount;
          _loadError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchQueryChanged(String query) {
    _filterCriteria = _filterCriteria.copyWith(searchQuery: query);
    _loadLibrary();
  }

  void _onApplyFilters(GameFilterCriteria criteria) {
    _filterCriteria = criteria;
    _loadLibrary();
  }

  void _onResetFilters() {
    if (_filterCriteria.isEmpty && _totalGamesCount > 0) {
      _filterCriteria = const GameFilterCriteria(includeHidden: true);
    } else {
      _filterCriteria = const GameFilterCriteria();
    }
    _loadLibrary();
  }

  void _toggleViewMode() {
    setState(() {
      switch (_viewMode) {
        case ViewMode.grid:
          _viewMode = ViewMode.list;
          break;
        case ViewMode.list:
          _viewMode = ViewMode.details;
          break;
        case ViewMode.details:
          _viewMode = ViewMode.grid;
          break;
      }
    });
  }

  void _showSortBottomSheet() {
    const sortChoices = [
      SortOption.titleAsc,
      SortOption.titleDesc,
      SortOption.playtimeDesc,
      SortOption.lastPlayedDesc,
      SortOption.scoreDesc,
      SortOption.releaseDesc,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sort Library',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ),
              const Divider(height: 1),
              ...sortChoices.map((opt) {
                final isSelected = _sortOption.field == opt.field && _sortOption.direction == opt.direction;
                return ListTile(
                  title: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected ? AppTheme.primaryLight : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primaryLight) : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    setState(() => _sortOption = opt);
                    _loadLibrary();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeFilters = _filterCriteria.activeFiltersCount;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Playnite Library'),
        actions: [
          // View Mode Toggle
          IconButton(
            icon: Icon(
              _viewMode == ViewMode.grid
                  ? Icons.grid_view
                  : (_viewMode == ViewMode.list ? Icons.view_list : Icons.view_headline),
            ),
            tooltip: 'Change View Mode',
            onPressed: _toggleViewMode,
          ),

          // Sort Button
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort Options',
            onPressed: _showSortBottomSheet,
          ),

          // Stats Dashboard Button
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Stats Dashboard',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StatsDashboardScreen(database: widget.database),
                ),
              );
            },
          ),

          // Delta Sync Button
          IconButton(
            icon: const Icon(Icons.sync, color: AppTheme.primaryLight),
            tooltip: 'Sync with Cloud',
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => SyncDialog(
                  database: widget.database,
                  onSyncCompleted: _loadLibrary,
                ),
              );
              if (mounted) {
                _loadLibrary();
              }
            },
          ),

          // Settings & Sync Configuration
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings & Cloud Sync',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SyncSettingsScreen(
                    database: widget.database,
                    onSettingsChanged: _loadLibrary,
                  ),
                ),
              );
              if (mounted) {
                _loadLibrary();
              }
            },
          ),
        ],
      ),
      endDrawer: FilterDrawer(
        currentCriteria: _filterCriteria,
        taxonomies: _taxonomies,
        onApply: _onApplyFilters,
        onReset: _onResetFilters,
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: LibrarySearchBar(
                    initialQuery: _filterCriteria.searchQuery,
                    onQueryChanged: _onSearchQueryChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                    if (activeFilters > 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$activeFilters',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Library summary header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _totalGamesCount > 0 && _games.length != _totalGamesCount
                      ? '${_games.length} of $_totalGamesCount games'
                      : '${_games.length} ${_games.length == 1 ? 'game' : 'games'} found',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                Text(
                  _sortOption.label,
                  style: const TextStyle(fontSize: 12, color: AppTheme.primaryLight, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Games Virtualized View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _loadLibrary,
                    child: _games.isEmpty ? _buildEmptyState() : _buildGamesView(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesView() {
    switch (_viewMode) {
      case ViewMode.grid:
        return LayoutBuilder(
          builder: (context, constraints) {
            // Adaptive column count based on viewport width
            final crossAxisCount = (constraints.maxWidth / 140).floor().clamp(2, 6);
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _games.length,
              itemBuilder: (context, index) => GameCardGrid(game: _games[index]),
            );
          },
        );

      case ViewMode.list:
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _games.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) => GameListTile(game: _games[index]),
        );

      case ViewMode.details:
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _games.length,
          itemBuilder: (context, index) => GameDetailsTile(game: _games[index]),
        );
    }
  }

  Widget _buildEmptyState() {
    final hasGamesInDb = _totalGamesCount > 0;
    final isFiltered = !_filterCriteria.isEmpty;

    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportConstraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadError != null) ...[
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to Load Library',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                        label: const Text(
                          'Retry Loading',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _loadLibrary,
                      ),
                    ] else if (hasGamesInDb) ...[
                      const Icon(
                        Icons.search_off,
                        size: 64,
                        color: AppTheme.primaryLight,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No games match your current filters',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You have $_totalGamesCount games in your local library, but none match the current filter or search criteria.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.clear_all, size: 18, color: Colors.white),
                        label: Text(
                          'Reset Filters & Show All $_totalGamesCount Games',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _onResetFilters,
                      ),
                    ] else if (isFiltered) ...[
                      const Icon(
                        Icons.search_off,
                        size: 64,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No games match your criteria',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Try clearing some filters or searching with a different term.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surfaceLight,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.clear_all, size: 16, color: Colors.white),
                        label: const Text('Clear All Filters', style: TextStyle(color: Colors.white)),
                        onPressed: _onResetFilters,
                      ),
                    ] else ...[
                      const Icon(
                        Icons.videogame_asset_outlined,
                        size: 64,
                        color: AppTheme.primaryLight,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to Playnite Companion',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your library is ready to sync! Connect your Google Drive or sync from local storage to view your Playnite collection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                        label: const Text(
                          'Configure Sync & Google Drive',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SyncSettingsScreen(
                                database: widget.database,
                                onSettingsChanged: _loadLibrary,
                              ),
                            ),
                          );
                          if (mounted) {
                            _loadLibrary();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        icon: const Icon(Icons.sync, size: 18, color: Colors.white),
                        label: const Text(
                          'Sync Library Now',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => SyncDialog(
                              database: widget.database,
                              onSyncCompleted: _loadLibrary,
                            ),
                          );
                          if (mounted) {
                            _loadLibrary();
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
