import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'widgets/completion_pie_chart.dart';
import 'widgets/most_played_leaderboard.dart';
import 'widgets/platform_breakdown_bar.dart';
import 'widgets/playtime_summary_card.dart';
import 'widgets/recent_activity_timeline.dart';

class StatsDashboardScreen extends StatefulWidget {
  final AppDatabase database;

  const StatsDashboardScreen({super.key, required this.database});

  @override
  State<StatsDashboardScreen> createState() => _StatsDashboardScreenState();
}

class _StatsDashboardScreenState extends State<StatsDashboardScreen> {
  late final StatsDao _statsDao;
  LibraryStats? _stats;
  bool _isLoading = true;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Library Statistics'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _stats == null || _stats!.totalGames == 0
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // Total playtime & overview metrics
                      PlaytimeSummaryCard(stats: _stats!),

                      // Completion Status Donut Chart
                      CompletionPieChart(completionBreakdown: _stats!.completionBreakdown),

                      // Playtime by Storefront / Source
                      PlatformBreakdownBar(
                        title: 'Playtime by Storefront',
                        icon: Icons.storefront,
                        distribution: _stats!.playtimeBySource,
                      ),

                      // Playtime by Platform
                      PlatformBreakdownBar(
                        title: 'Playtime by Platform',
                        icon: Icons.devices,
                        distribution: _stats!.playtimeByPlatform,
                      ),

                      // Top 10 Most Played Games Leaderboard
                      MostPlayedLeaderboard(topGames: _stats!.topPlayedGames),

                      // Recent Play Sessions Timeline
                      RecentActivityTimeline(sessions: _stats!.recentSessions),

                      const SizedBox(height: 32),
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
