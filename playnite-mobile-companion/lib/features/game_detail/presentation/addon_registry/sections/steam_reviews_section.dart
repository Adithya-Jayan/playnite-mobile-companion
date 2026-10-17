import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

class SteamReviewsSection implements IAddonSectionWidget {
  const SteamReviewsSection();

  @override
  String get addonKey => 'steam_reviews_viewer';

  @override
  int get displayOrder => 60;

  @override
  String get title => 'Steam Reviews';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    final positivePercent = (addonData['positive_percent'] as num?)?.toInt();
    final totalReviews = (addonData['total_reviews'] as num?)?.toInt() ?? 0;
    final scoreDesc = addonData['review_score_desc'] as String? ?? 'Positive';

    if (totalReviews == 0 && positivePercent == null) {
      return const SizedBox.shrink();
    }

    final isPositive = (positivePercent ?? 70) >= 70;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isPositive ? AppTheme.accentGreen : AppTheme.accentRed).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPositive ? Icons.thumb_up : Icons.thumb_down,
                color: isPositive ? AppTheme.accentGreen : AppTheme.accentRed,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scoreDesc,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? AppTheme.accentGreen : AppTheme.accentRed,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    positivePercent != null
                        ? '$positivePercent% of $totalReviews user reviews are positive'
                        : '$totalReviews user reviews',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
