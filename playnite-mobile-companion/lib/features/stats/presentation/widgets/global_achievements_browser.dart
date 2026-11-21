import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/ui/achievement_detail_modal.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';

class GlobalAchievementsBrowser extends StatefulWidget {
  final StatsDao statsDao;
  final ValueChanged<String>? onGameTap;

  const GlobalAchievementsBrowser({
    super.key,
    required this.statsDao,
    this.onGameTap,
  });

  @override
  State<GlobalAchievementsBrowser> createState() => _GlobalAchievementsBrowserState();
}

class _GlobalAchievementsBrowserState extends State<GlobalAchievementsBrowser> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  static const int _pageSize = 50;
  List<GlobalAchievementEntry> _achievements = [];
  int _totalCount = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _searchQuery = '';
  GlobalAchievementSort _currentSort = GlobalAchievementSort.unlockDateDesc;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 200 && !_isLoading && !_isLoadingMore && _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _achievements.clear();
      _hasMore = true;
    });

    try {
      final results = await widget.statsDao.getGlobalAchievementsPaged(
        limit: _pageSize,
        offset: 0,
        searchQuery: _searchQuery,
        sort: _currentSort,
      );
      final count = await widget.statsDao.getGlobalAchievementsCount(
        searchQuery: _searchQuery,
      );

      if (mounted) {
        setState(() {
          _achievements = results;
          _totalCount = count;
          _isLoading = false;
          _hasMore = results.length >= _pageSize;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final results = await widget.statsDao.getGlobalAchievementsPaged(
        limit: _pageSize,
        offset: _achievements.length,
        searchQuery: _searchQuery,
        sort: _currentSort,
      );

      if (mounted) {
        setState(() {
          _achievements.addAll(results);
          _isLoadingMore = false;
          _hasMore = results.length >= _pageSize;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_searchQuery != val) {
        setState(() {
          _searchQuery = val;
        });
        _loadInitial();
      }
    });
  }

  void _onSortChanged(GlobalAchievementSort? newSort) {
    if (newSort == null || newSort == _currentSort) return;
    setState(() {
      _currentSort = newSort;
    });
    _loadInitial();
  }

  String _formatDate(String? utcString) {
    if (utcString == null || utcString.isEmpty) return '';
    try {
      final dt = DateTime.parse(utcString).toLocal();
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return '';
    }
  }

  Color _getRarityColor(double? pct) {
    if (pct == null) return AppTheme.textMuted;
    if (pct <= 5.0) return Colors.amber;
    if (pct <= 15.0) return AppTheme.accentPurple;
    if (pct <= 30.0) return AppTheme.accentCyan;
    if (pct <= 50.0) return AppTheme.accentGreen;
    return AppTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search & Controls Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              // Search input
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search achievements or games...',
                  hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textMuted),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Sort dropdown + Count chip
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<GlobalAchievementSort>(
                          value: _currentSort,
                          isExpanded: true,
                          icon: const Icon(Icons.sort, size: 18, color: AppTheme.primaryLight),
                          dropdownColor: AppTheme.cardColor,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                          onChanged: _onSortChanged,
                          items: const [
                            DropdownMenuItem(
                              value: GlobalAchievementSort.unlockDateDesc,
                              child: Text('Newest Unlocked'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.unlockDateAsc,
                              child: Text('Oldest Unlocked'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.rarityAsc,
                              child: Text('Rarest First'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.rarityDesc,
                              child: Text('Most Common'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.scoreDesc,
                              child: Text('Highest Score'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.scoreAsc,
                              child: Text('Lowest Score'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.gameTitleAsc,
                              child: Text('Game Title (A-Z)'),
                            ),
                            DropdownMenuItem(
                              value: GlobalAchievementSort.titleAsc,
                              child: Text('Achievement (A-Z)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Text(
                      '$_totalCount unlocked',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List Area
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _achievements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events_outlined, size: 48, color: AppTheme.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No achievements matching "$_searchQuery"'
                                : 'No unlocked achievements found',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _loadInitial,
                      child: ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _achievements.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index >= _achievements.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }

                          final item = _achievements[index];
                          final hasIcon = item.urlUnlocked != null && item.urlUnlocked!.trim().isNotEmpty;
                          final dateStr = _formatDate(item.dateUnlockedUtc);
                          final rarityColor = _getRarityColor(item.percent);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            onTap: () {
                              AchievementDetailModal.show(
                                context,
                                name: item.name,
                                description: item.description,
                                gameName: item.gameName,
                                iconUrl: item.urlUnlocked,
                                isUnlocked: true,
                                dateUnlockedUtc: item.dateUnlockedUtc,
                                percent: item.percent,
                                gamerScore: item.gamerScore,
                                isHidden: item.isHidden,
                                onViewGame: () => widget.onGameTap?.call(item.gameId),
                              );
                            },
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.primaryLight.withValues(alpha: 0.5),
                                  width: 1.2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: hasIcon
                                    ? PlayniteCachedImage(
                                        mediaId: item.urlUnlocked,
                                        fit: BoxFit.cover,
                                        placeholder: const Center(
                                          child: Icon(Icons.emoji_events, size: 22, color: Colors.amber),
                                        ),
                                        errorWidget: const Center(
                                          child: Icon(Icons.emoji_events, size: 22, color: Colors.amber),
                                        ),
                                      )
                                    : const Center(
                                        child: Icon(Icons.emoji_events, size: 22, color: Colors.amber),
                                      ),
                              ),
                            ),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.gameName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.accentPurple,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (dateStr.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '• $dateStr',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (item.percent != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: rarityColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: rarityColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star, size: 10, color: rarityColor),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${item.percent!.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: rarityColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (item.gamerScore != null && item.gamerScore! > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '⚡ ${item.gamerScore!.toInt()} pts',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
