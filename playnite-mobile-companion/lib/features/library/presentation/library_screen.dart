import 'dart:math';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/library_preferences_service.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/settings/presentation/settings_screen.dart';
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

  final ScrollController _scrollController = ScrollController();

  List<UnifiedGamePayload> _games = [];
  int _totalGamesCount = 0;
  int _filteredGamesCount = 0;
  FilterTaxonomies _taxonomies = const FilterTaxonomies();
  bool _isLoading = true;
  String? _loadError;
  int _currentTabIndex = 0;
  bool _hasPendingSync = false;
  String? _scrubbingLetter;
  Map<String, int> _letterIndexMap = {};

  ViewMode _viewMode = ViewMode.grid;
  SortOption _sortOption = SortOption.titleAsc;
  GameFilterCriteria _filterCriteria = const GameFilterCriteria();
  late final GallerySettingsRepository _galleryRepo;
  late final LibraryPreferencesService _prefsService;
  GallerySettings _gallerySettings = const GallerySettings();

  GameFilterCriteria get _effectiveCriteria {
    return _filterCriteria.copyWith(
      includeUserHidden: _gallerySettings.includeUserHiddenGames,
      includeDuplicateHider: _gallerySettings.includeDuplicateHiderGames,
      ratingScoreSource: _gallerySettings.ratingScoreSource,
    );
  }

  bool _showScrollToTop = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _gameDao = GameDao(widget.database);
    _taxonomyDao = TaxonomyDao(widget.database);
    _galleryRepo = GallerySettingsRepository(widget.database);
    _prefsService = LibraryPreferencesService();
    _scrollController.addListener(_onScroll);
    _restorePreferencesAndLoad();
    _checkPendingSyncStatus();
  }

  Future<void> _checkPendingSyncStatus() async {
    try {
      final total = await _gameDao.getGamesCount();
      if (total == 0) {
        if (mounted) setState(() => _hasPendingSync = true);
        return;
      }
      final syncEntries = await SyncMetaDao(widget.database).getAllEntriesMap();
      if (syncEntries.isEmpty) {
        if (mounted) setState(() => _hasPendingSync = true);
        return;
      }
      if (mounted) setState(() => _hasPendingSync = false);
    } catch (_) {
      if (mounted) setState(() => _hasPendingSync = false);
    }
  }

  void _buildLetterIndexMap() {
    final map = <String, int>{};
    for (int i = 0; i < _games.length; i++) {
      final title = (_games[i].sortingName.isNotEmpty ? _games[i].sortingName : _games[i].name).trim().toUpperCase();
      if (title.isEmpty) continue;
      final firstChar = title[0];
      final letterKey = RegExp(r'^[A-Z]').hasMatch(firstChar) ? firstChar : '#';
      map.putIfAbsent(letterKey, () => i);
    }
    _letterIndexMap = map;
  }

  Future<void> _restorePreferencesAndLoad() async {
    try {
      final savedSort = await _prefsService.loadSortOption();
      final savedView = await _prefsService.loadViewMode();
      final savedCriteria = await _prefsService.loadFilterCriteria();
      final gallerySettings = await _galleryRepo.loadSettings();

      if (mounted) {
        setState(() {
          _sortOption = savedSort;
          if (savedView != null) {
            _viewMode = ViewMode.values.firstWhere((v) => v.name == savedView, orElse: () => ViewMode.grid);
          }
          if (savedCriteria != null) {
            _filterCriteria = savedCriteria;
          }
          _gallerySettings = gallerySettings;
        });
      }
    } catch (_) {}
    _loadLibrary();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final showToTop = _scrollController.offset > 600;
      if (showToTop != _showScrollToTop) {
        setState(() => _showScrollToTop = showToTop);
      }
    }
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _gallerySettings = await _galleryRepo.loadSettings();
      final effective = _effectiveCriteria;
      final totalCount = await _gameDao.getGamesCount();
      final taxonomies = await _taxonomyDao.getAvailableTaxonomies();
      final int filteredCount;
      if (effective.isEmpty) {
        filteredCount = totalCount;
      } else {
        filteredCount = await _gameDao.getFilteredGamesCount(criteria: effective);
      }
      final allGames = await _gameDao.getFilteredGames(
        criteria: effective,
        sort: _sortOption,
      );

      if (mounted) {
        setState(() {
          _games = allGames;
          _taxonomies = taxonomies;
          _totalGamesCount = totalCount;
          _filteredGamesCount = filteredCount;
          _isLoading = false;
          _loadError = null;
        });
        _buildLetterIndexMap();
      }
      _checkPendingSyncStatus();
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
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _filterCriteria = _filterCriteria.copyWith(searchQuery: query);
    _loadLibrary();
  }

  void _onApplyFilters(GameFilterCriteria criteria) {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() => _filterCriteria = criteria);
    _prefsService.saveFilterCriteria(criteria);
    _loadLibrary();
  }

  void _onResetFilters() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    const resetCriteria = GameFilterCriteria();
    setState(() => _filterCriteria = resetCriteria);
    _prefsService.saveFilterCriteria(resetCriteria);
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
    _prefsService.saveViewMode(_viewMode.name);
  }

  void _pickSurpriseGame() {
    if (_games.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No games available in current filter selection.')),
      );
      return;
    }
    final unplayed = _games.where((g) => g.playtimeSeconds == 0 || g.playCount == 0).toList();
    final pool = unplayed.isNotEmpty ? unplayed : _games;
    final randomGame = pool[Random().nextInt(pool.length)];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎲 Surprise Pick: ${randomGame.name}'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppTheme.primary,
      ),
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameDetailScreen(game: randomGame)),
    );
  }

  void _showSortBottomSheet() {
    final sortChoices = [
      SortOption.titleAsc,
      SortOption.titleDesc,
      SortOption.random,
      SortOption.addedDesc,
      const SortOption(field: SortField.addedDate, direction: SortDirection.ascending),
      SortOption.playtimeDesc,
      const SortOption(field: SortField.playtime, direction: SortDirection.ascending),
      SortOption.lastPlayedDesc,
      const SortOption(field: SortField.lastPlayed, direction: SortDirection.ascending),
      const SortOption(field: SortField.timesPlayed, direction: SortDirection.descending),
      SortOption.communityScoreDesc,
      SortOption.criticScoreDesc,
      SortOption.releaseDesc,
      const SortOption(field: SortField.releaseDate, direction: SortDirection.ascending),
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
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: sortChoices.map((opt) {
                    final isSelected = _sortOption.field == opt.field && _sortOption.direction == opt.direction;
                    return ListTile(
                      dense: true,
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
                        _prefsService.saveSortOption(opt);
                        _loadLibrary();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildLibraryAppBar() {
    return AppBar(
      leading: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/applogo.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      leadingWidth: 42,
      titleSpacing: 8,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Playnite',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          if (_totalGamesCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_totalGamesCount',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Surprise Me (Random Game Picker)
        IconButton(
          icon: const Icon(Icons.casino_outlined),
          tooltip: 'Surprise Me',
          onPressed: _pickSurpriseGame,
        ),

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

        // Delta Sync Button with Pending Alert Dot
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.sync, color: AppTheme.primaryLight),
              if (_hasPendingSync)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.amberAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          tooltip: _hasPendingSync ? 'Sync Library (Updates Pending)' : 'Sync Library',
          onPressed: () async {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => SyncDialog(
                database: widget.database,
                onSyncCompleted: () {
                  _checkPendingSyncStatus();
                  _loadLibrary();
                },
              ),
            );
            if (mounted) {
              _checkPendingSyncStatus();
              _loadLibrary();
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeFilters = _filterCriteria.activeFiltersCount;

    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentTabIndex != 0) {
          setState(() => _currentTabIndex = 0);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.background,
        drawerEnableOpenDragGesture: false,
        endDrawerEnableOpenDragGesture: false,
        appBar: _currentTabIndex == 0 ? _buildLibraryAppBar() : null,
        endDrawer: _currentTabIndex == 0
            ? FilterDrawer(
                currentCriteria: _filterCriteria,
                taxonomies: _taxonomies,
                onApply: _onApplyFilters,
                onReset: _onResetFilters,
              )
            : null,
        body: _buildCurrentTabBody(activeFilters),
        floatingActionButton: (_currentTabIndex == 0 && _showScrollToTop)
            ? FloatingActionButton.small(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                tooltip: 'Scroll to Top',
                onPressed: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: const Icon(Icons.keyboard_arrow_up, size: 24),
              )
            : null,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 0.8)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentTabIndex,
            backgroundColor: AppTheme.surface,
            selectedItemColor: AppTheme.primary,
            unselectedItemColor: AppTheme.textMuted,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: BottomNavigationBarType.fixed,
            onTap: (index) {
              if (index == 0 && _currentTabIndex == 0 && _scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              }
              setState(() => _currentTabIndex = index);
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.video_library_outlined),
                activeIcon: Icon(Icons.video_library),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: 'Statistics',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTabBody(int activeFilters) {
    switch (_currentTabIndex) {
      case 1:
        return StatsDashboardScreen(database: widget.database);
      case 2:
        return SettingsScreen(
          database: widget.database,
          onSettingsChanged: _loadLibrary,
        );
      case 0:
      default:
        return _buildLibraryBody(activeFilters);
    }
  }

  Widget _buildLibraryBody(int activeFilters) {
    return Column(
      children: [
        // Utility Filter Mode Active Banner (Triage / Diagnostic view)
        if (_filterCriteria.utilityMode != UtilityFilterMode.none)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _filterCriteria.utilityMode == UtilityFilterMode.onlyHidden
                ? Colors.amber.withValues(alpha: 0.12)
                : (_filterCriteria.utilityMode == UtilityFilterMode.onlyDuplicates
                    ? Colors.purple.withValues(alpha: 0.12)
                    : Colors.blue.withValues(alpha: 0.12)),
            child: Row(
              children: [
                Icon(
                  _filterCriteria.utilityMode == UtilityFilterMode.onlyHidden
                      ? Icons.visibility_off
                      : (_filterCriteria.utilityMode == UtilityFilterMode.onlyDuplicates
                          ? Icons.copy_all
                          : (_filterCriteria.utilityMode == UtilityFilterMode.onlyUnplayed
                              ? Icons.schedule
                              : Icons.build_circle_outlined)),
                  color: _filterCriteria.utilityMode == UtilityFilterMode.onlyHidden
                      ? Colors.amber
                      : (_filterCriteria.utilityMode == UtilityFilterMode.onlyDuplicates
                          ? Colors.purpleAccent
                          : Colors.lightBlueAccent),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _getUtilityBannerText(_filterCriteria.utilityMode),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _filterCriteria.utilityMode == UtilityFilterMode.onlyHidden
                          ? Colors.amber
                          : (_filterCriteria.utilityMode == UtilityFilterMode.onlyDuplicates
                              ? Colors.purpleAccent
                              : Colors.lightBlueAccent),
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    final updated = _filterCriteria.copyWith(clearUtility: true);
                    setState(() => _filterCriteria = updated);
                    _prefsService.saveFilterCriteria(updated);
                    _loadLibrary();
                  },
                  child: const Text('Clear', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                ),
              ],
            ),
          ),

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
              const SizedBox(width: 4),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    tooltip: 'Filter Library',
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
              // Sort Button (To the right of the filter button)
              IconButton(
                icon: const Icon(Icons.swap_vert),
                tooltip: 'Sort Library',
                onPressed: _showSortBottomSheet,
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
                _summaryHeaderText(),
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
    );
  }

  String _getUtilityBannerText(UtilityFilterMode mode) {
    switch (mode) {
      case UtilityFilterMode.onlyHidden:
        return 'Triage: Showing only hidden items';
      case UtilityFilterMode.onlyDuplicates:
        return 'Triage: Showing only DuplicateHider copies';
      case UtilityFilterMode.onlyUnplayed:
        return 'Triage: Showing only unplayed games (0h)';
      case UtilityFilterMode.missingCovers:
        return 'Diagnostic: Showing games missing cover art';
      case UtilityFilterMode.missingMicrotrailers:
        return 'Diagnostic: Showing games missing microtrailers';
      case UtilityFilterMode.none:
        return '';
    }
  }

  String _summaryHeaderText() {
    if (_totalGamesCount == 0) return '0 games';
    final hasFilters = !_filterCriteria.isEmpty;
    if (hasFilters) {
      if (_filteredGamesCount == 0) return '0 of $_totalGamesCount games match';
      if (_games.length < _filteredGamesCount) {
        return 'Showing ${_games.length} of $_filteredGamesCount matching games';
      }
      return '$_filteredGamesCount matching ${_filteredGamesCount == 1 ? 'game' : 'games'}';
    } else {
      if (_games.length < _totalGamesCount) {
        return 'Showing ${_games.length} of $_totalGamesCount games';
      }
      return '$_totalGamesCount ${_totalGamesCount == 1 ? 'game' : 'games'}';
    }
  }

  Widget _buildGamesView() {
    Widget scrollView;
    switch (_viewMode) {
      case ViewMode.grid:
        scrollView = LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = (constraints.maxWidth / 140).floor().clamp(2, 6);
            return GridView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              cacheExtent: 500.0,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _games.length,
              itemBuilder: (context, index) {
                return GameCardGrid(
                  key: ValueKey(_games[index].id),
                  game: _games[index],
                );
              },
            );
          },
        );
        break;

      case ViewMode.list:
        scrollView = ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          cacheExtent: 500.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemCount: _games.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return GameListTile(
              key: ValueKey(_games[index].id),
              game: _games[index],
            );
          },
        );
        break;

      case ViewMode.details:
        scrollView = ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          cacheExtent: 500.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemCount: _games.length,
          itemBuilder: (context, index) {
            return GameDetailsTile(
              key: ValueKey(_games[index].id),
              game: _games[index],
            );
          },
        );
        break;
    }

    final showScrubber = _sortOption.field == SortField.title && _games.length >= 10;
    return Stack(
      children: [
        Scrollbar(
          controller: _scrollController,
          interactive: true,
          thickness: 6.0,
          radius: const Radius.circular(8),
          child: scrollView,
        ),
        if (showScrubber) _buildAlphabetScrubber(),
      ],
    );
  }

  void _scrollToLetter(String letter, {bool animate = true}) {
    if (_games.isEmpty || !_scrollController.hasClients) return;
    final targetIndex = _letterIndexMap[letter];
    if (targetIndex != null && targetIndex >= 0) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final double estimatedOffset = (targetIndex / _games.length) * maxScroll;
      final clampedOffset = estimatedOffset.clamp(0.0, maxScroll);
      if (animate) {
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(clampedOffset);
      }
    }
  }

  void _onScrub(Offset localPosition, double totalHeight, List<String> letters, {bool isTap = false}) {
    if (totalHeight <= 0 || letters.isEmpty) return;
    final itemHeight = totalHeight / letters.length;
    final index = (localPosition.dy / itemHeight).floor().clamp(0, letters.length - 1);
    final letter = letters[index];
    if (_scrubbingLetter != letter) {
      setState(() => _scrubbingLetter = letter);
      _scrollToLetter(letter, animate: isTap);
    }
  }

  Widget _buildAlphabetScrubber() {
    const letters = [
      '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',
      'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
      'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
    ];

    return Positioned(
      right: 2,
      top: 8,
      bottom: 8,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Floating bubble HUD while dragging/scrubbing
            if (_scrubbingLetter != null) ...[
              Container(
                width: 50,
                height: 50,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _scrubbingLetter!,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],

            // Alphabet scrubber rail with drag and tap gesture
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (details) => _onScrub(details.localPosition, constraints.maxHeight, letters),
                  onVerticalDragUpdate: (details) => _onScrub(details.localPosition, constraints.maxHeight, letters),
                  onVerticalDragEnd: (_) => setState(() => _scrubbingLetter = null),
                  onVerticalDragCancel: () => setState(() => _scrubbingLetter = null),
                  onTapDown: (details) => _onScrub(details.localPosition, constraints.maxHeight, letters, isTap: true),
                  onTapUp: (_) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) setState(() => _scrubbingLetter = null);
                    });
                  },
                  onTapCancel: () => setState(() => _scrubbingLetter = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: letters.map((l) {
                        final isAvailable = _letterIndexMap.containsKey(l);
                        final isHighlighted = _scrubbingLetter == l;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0.8, horizontal: 2.0),
                          child: Text(
                            l,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.bold,
                              color: isHighlighted
                                  ? AppTheme.primaryLight
                                  : (isAvailable ? AppTheme.textPrimary : AppTheme.textMuted.withValues(alpha: 0.35)),
                              height: 1.1,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
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
                            barrierDismissible: false,
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
