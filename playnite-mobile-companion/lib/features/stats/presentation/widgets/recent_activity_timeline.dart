import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/stats_dao.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';

/// Represents adjacent play sessions for the same game clubbed together.
class GroupedRecentActivity {
  final String gameId;
  final String gameName;
  final String? coverDriveFileId;
  final List<RecentSessionEntry> sessions;

  GroupedRecentActivity({
    required this.gameId,
    required this.gameName,
    this.coverDriveFileId,
    required this.sessions,
  });

  int get totalElapsedSeconds => sessions.fold(0, (sum, s) => sum + s.elapsedSeconds);
  int get sessionCount => sessions.length;

  RecentSessionEntry get latestSession => sessions.first;
  RecentSessionEntry get earliestSession => sessions.last;
}

class RecentActivityTimeline extends StatefulWidget {
  final List<RecentSessionEntry> sessions;

  const RecentActivityTimeline({super.key, required this.sessions});

  @override
  State<RecentActivityTimeline> createState() => _RecentActivityTimelineState();
}

class _RecentActivityTimelineState extends State<RecentActivityTimeline> {
  final Set<int> _expandedGroupIndices = {};

  List<GroupedRecentActivity> _groupAdjacentSessions(List<RecentSessionEntry> rawSessions) {
    if (rawSessions.isEmpty) return const [];

    final groups = <GroupedRecentActivity>[];
    GroupedRecentActivity? currentGroup;

    for (final session in rawSessions) {
      if (currentGroup == null || currentGroup.gameId != session.gameId) {
        currentGroup = GroupedRecentActivity(
          gameId: session.gameId,
          gameName: session.gameName,
          coverDriveFileId: session.coverDriveFileId,
          sessions: [session],
        );
        groups.add(currentGroup);
      } else {
        currentGroup.sessions.add(session);
      }
    }

    return groups;
  }

  DateTime? _parseDate(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  String _formatSingleDate(String rawUtc) {
    final dt = _parseDate(rawUtc)?.toLocal();
    if (dt == null) {
      return rawUtc.length >= 16 ? rawUtc.substring(0, 16).replaceAll('T', ' ') : rawUtc;
    }
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today at ${DateFormat('h:mm a').format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday at ${DateFormat('h:mm a').format(dt)}';
    }
    if (dt.year == now.year) {
      return DateFormat('MMM d • h:mm a').format(dt);
    }
    return DateFormat('MMM d, yyyy • h:mm a').format(dt);
  }

  String _formatDateRange(String earliestUtc, String latestUtc) {
    final eDt = _parseDate(earliestUtc)?.toLocal();
    final lDt = _parseDate(latestUtc)?.toLocal();

    if (eDt == null || lDt == null) {
      return 'Multiple sessions';
    }

    // Same day
    if (eDt.year == lDt.year && eDt.month == lDt.month && eDt.day == lDt.day) {
      return DateFormat('MMM d, yyyy').format(lDt);
    }

    // Same month & year
    if (eDt.year == lDt.year && eDt.month == lDt.month) {
      return '${DateFormat('MMM d').format(eDt)} – ${DateFormat('d, yyyy').format(lDt)}';
    }

    // Same year
    if (eDt.year == lDt.year) {
      return '${DateFormat('MMM d').format(eDt)} – ${DateFormat('MMM d, yyyy').format(lDt)}';
    }

    // Different years
    return '${DateFormat('MMM d, yyyy').format(eDt)} – ${DateFormat('MMM d, yyyy').format(lDt)}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) return const SizedBox.shrink();

    final groups = _groupAdjacentSessions(widget.sessions);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, color: AppTheme.accentGreen, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                Text(
                  '${widget.sessions.length} sessions',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: groups.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final group = groups[index];
                final isExpanded = _expandedGroupIndices.contains(index);
                final hasMultiple = group.sessionCount > 1;
                final totalDurationStr =
                    DurationFormatter.formatSecondsToHoursMinutes(group.totalElapsedSeconds);

                return InkWell(
                  onTap: hasMultiple
                      ? () {
                          setState(() {
                            if (isExpanded) {
                              _expandedGroupIndices.remove(index);
                            } else {
                              _expandedGroupIndices.add(index);
                            }
                          });
                        }
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Game Cover or Game Icon
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 36,
                                height: 48,
                                color: AppTheme.surfaceLight,
                                child: (group.coverDriveFileId != null && group.coverDriveFileId!.isNotEmpty)
                                    ? PlayniteCachedImage(
                                        mediaId: group.coverDriveFileId,
                                        fit: BoxFit.cover,
                                        placeholder: const Center(
                                          child: Icon(Icons.videogame_asset_outlined,
                                              color: AppTheme.textMuted, size: 18),
                                        ),
                                        errorWidget: const Center(
                                          child: Icon(Icons.videogame_asset_outlined,
                                              color: AppTheme.textMuted, size: 18),
                                        ),
                                      )
                                    : const Center(
                                        child: Icon(Icons.videogame_asset_outlined,
                                            color: AppTheme.accentGreen, size: 20),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Title & Compressed Subtitle
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.gameName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (hasMultiple) ...[
                                    Text(
                                      '$totalDurationStr over ${group.sessionCount} sessions',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.accentGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _formatDateRange(
                                        group.earliestSession.dateSessionUtc,
                                        group.latestSession.dateSessionUtc,
                                      ),
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ] else ...[
                                    Text(
                                      _formatSingleDate(group.latestSession.dateSessionUtc),
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),

                            // Total Duration Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                totalDurationStr,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),

                            // Expand Chevron for Multi-Session Groups
                            if (hasMultiple) ...[
                              const SizedBox(width: 4),
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 20,
                                color: AppTheme.textMuted,
                              ),
                            ],
                          ],
                        ),

                        // Expanded Individual Sessions Breakdown
                        if (hasMultiple && isExpanded) ...[
                          const SizedBox(height: 8),
                          Container(
                            margin: const EdgeInsets.only(left: 48, top: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLight.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.dividerColor.withValues(alpha: 0.5),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              children: group.sessions.map((session) {
                                final sessionDuration =
                                    DurationFormatter.formatSecondsToHoursMinutes(session.elapsedSeconds);
                                final sessionDate = _formatSingleDate(session.dateSessionUtc);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.play_arrow_rounded,
                                          size: 14, color: AppTheme.accentGreen),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          sessionDate,
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                        ),
                                      ),
                                      Text(
                                        sessionDuration,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
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
}
