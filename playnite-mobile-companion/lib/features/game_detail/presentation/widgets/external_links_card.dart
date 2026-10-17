import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalLinksCard extends StatelessWidget {
  final List<LinkItem> links;

  const ExternalLinksCard({super.key, required this.links});

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link, color: AppTheme.primaryLight, size: 20),
                SizedBox(width: 8),
                Text(
                  'External Links',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: links.map((link) {
                return ActionChip(
                  avatar: const Icon(Icons.open_in_new, size: 14, color: AppTheme.primary),
                  label: Text(link.name.isNotEmpty ? link.name : 'Link'),
                  onPressed: () {
                    if (link.url.isNotEmpty) {
                      launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
