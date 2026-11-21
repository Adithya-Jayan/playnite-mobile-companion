import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'widgets/completion_pie_chart.dart';
import 'widgets/most_played_leaderboard.dart';
import 'widgets/platform_breakdown_bar.dart';
import 'widgets/playtime_summary_card.dart';
import 'widgets/recent_activity_timeline.dart';
import 'widgets/global_achievements_browser.dart';

class StatsDashboardScreen extends StatefulWidget {
  final AppDatabase database;

  const StatsDashboardScreen({super.key, required this.database});

  @override
  State<StatsDashboardScreen> createState() => _StatsDashboardScreenState();
}

enum StatsSectionKey {
  overview,
  completion,
  storefronts,
  platforms,
  topPlayed,
  recentActivity,
  recentAchievements,
}

class _StatsDashboardScreenState extends State<StatsDashboardScreen> {
  late final StatsDao _statsDao;
  LibraryStats? _stats;
  bool _isLoading = true;
  final Set<StatsSectionKey> _expandedSections = Set.from(StatsSectionKey.values);

  @override
  void initState() {
    super.initState();
    _statsDao = StatsDao(widget.database);
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _statsDao.calculateLibraryStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToGame(String gameId) async {
    try {
      final game = await GameDao(widget.database).getGameById(gameId);
      if (game != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GameDetailScreen(game: game)),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to game $gameId: $e');
    }
  }

  void _toggleAllSections() {
    setState(() {
      if (_expandedSections.isEmpty) {
        _expandedSections.addAll(StatsSectionKey.values);
      } else {
        _expandedSections.clear();
      }
    });
  }

  void _toggleSection(StatsSectionKey key, bool expanded) {
    setState(() {
      if (expanded) {
        _expandedSections.add(key);
      } else {
        _expandedSections.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final anyExpanded = _expandedSections.isNotEmpty;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Library Statistics'),
          bottom: const TabBar(
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            labelColor: AppTheme.primaryLight,
            unselectedLabelColor: AppTheme.textMuted,
            tabs: [
              Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 20)),
              Tab(text: 'Activity', icon: Icon(Icons.history, size: 20)),
              Tab(text: 'Achievements', icon: Icon(Icons.emoji_events_outlined, size: 20)),
            ],
          ),
          actions: [
            if (_stats != null && _stats!.totalGames > 0)
              IconButton(
                icon: Icon(
                  anyExpanded ? Icons.unfold_less : Icons.unfold_more,
                  color: AppTheme.textPrimary,
                ),
                tooltip: anyExpanded ? 'Collapse all sections' : 'Expand all sections',
                onPressed: _toggleAllSections,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _stats == null || _stats!.totalGames == 0
                ? _buildEmptyState()
                : TabBarView(
                    children: [
                      // Tab 1: Overview
                      RefreshIndicator(
                        color: AppTheme.primary,
                        onRefresh: _loadStats,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            PlaytimeSummaryCard(
                              stats: _stats!,
                              isExpanded: _expandedSections.contains(StatsSectionKey.overview),
                              onToggle: (v) => _toggleSection(StatsSectionKey.overview, v),
                            ),
                            CompletionPieChart(
                              completionBreakdown: _stats!.completionBreakdown,
                              isExpanded: _expandedSections.contains(StatsSectionKey.completion),
                              onToggle: (v) => _toggleSection(StatsSectionKey.completion, v),
                            ),
                            PlatformBreakdownBar(
                              title: 'Playtime by Storefront',
                              icon: Icons.storefront,
                              distribution: _stats!.playtimeBySource,
                              isExpanded: _expandedSections.contains(StatsSectionKey.storefronts),
                              onToggle: (v) => _toggleSection(StatsSectionKey.storefronts, v),
                            ),
                            PlatformBreakdownBar(
                              title: 'Playtime by Platform',
                              icon: Icons.devices,
                              distribution: _stats!.playtimeByPlatform,
                              isExpanded: _expandedSections.contains(StatsSectionKey.platforms),
                              onToggle: (v) => _toggleSection(StatsSectionKey.platforms, v),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),

                      // Tab 2: Activity
                      RefreshIndicator(
                        color: AppTheme.primary,
                        onRefresh: _loadStats,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            MostPlayedLeaderboard(
                              topGames: _stats!.topPlayedGames,
                              isExpanded: _expandedSections.contains(StatsSectionKey.topPlayed),
                              onToggle: (v) => _toggleSection(StatsSectionKey.topPlayed, v),
                              onGameTap: _navigateToGame,
                            ),
                            RecentActivityTimeline(
                              sessions: _stats!.recentSessions,
                              isExpanded: _expandedSections.contains(StatsSectionKey.recentActivity),
                              onToggle: (v) => _toggleSection(StatsSectionKey.recentActivity, v),
                              onGameTap: _navigateToGame,
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),

                      // Tab 3: Achievements
                      GlobalAchievementsBrowser(
                        statsDao: _statsDao,
                        onGameTap: _navigateToGame,
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart, size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text(
            'No statistics available yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            'Sync your library to see your playtime, completion, and achievements breakdown.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
