import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:url_launcher/url_launcher.dart';
import '../i_addon_widget.dart';

class DlcSection implements IAddonSectionWidget {
  const DlcSection();

  @override
  String get addonKey => 'check_dlc';

  @override
  int get displayOrder => 40;

  @override
  String get title => 'DLC & Expansions';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    final rawDlcs = addonData['dlcs'];
    final dlcs = (rawDlcs is List)
        ? rawDlcs.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    if (dlcs.isEmpty) return const SizedBox.shrink();

    final ownedCount = dlcs.where((d) => d['is_owned'] == true).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.extension_outlined, color: AppTheme.primaryLight, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Downloadable Content ($ownedCount / ${dlcs.length} Owned)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dlcs.length > 8 ? 8 : dlcs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final dlc = dlcs[index];
                final name = dlc['name'] as String? ?? 'DLC Item';
                final isOwned = dlc['is_owned'] == true;
                final price = (dlc['price'] as num?)?.toDouble();
                final currency = dlc['currency'] as String? ?? '\$';
                final url = dlc['url'] as String?;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isOwned ? Icons.check_circle : Icons.shopping_cart_outlined,
                    color: isOwned ? AppTheme.accentGreen : AppTheme.textMuted,
                    size: 20,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                  ),
                  subtitle: price != null
                      ? Text(
                          '$currency${price.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOwned
                              ? AppTheme.accentGreen.withValues(alpha: 0.15)
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isOwned ? AppTheme.accentGreen : AppTheme.dividerColor,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isOwned ? 'Owned' : 'Unowned',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOwned ? AppTheme.accentGreen : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (url != null && url.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.textMuted),
                          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            if (dlcs.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '+ ${dlcs.length - 8} more DLC items',
                    style: const TextStyle(color: AppTheme.primaryLight, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
