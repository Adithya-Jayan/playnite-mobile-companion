import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'addon_registry/addon_section_registry.dart';
import 'widgets/external_links_card.dart';
import 'widgets/metadata_chips_row.dart';
import 'widgets/microtrailer_player.dart';
import 'widgets/play_time_card.dart';

class GameDetailScreen extends StatefulWidget {
  final UnifiedGamePayload game;

  const GameDetailScreen({super.key, required this.game});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  bool _isDescriptionExpanded = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final developer = game.developers.isNotEmpty ? game.developers.first.name : null;
    final publisher = game.publishers.isNotEmpty ? game.publishers.first.name : null;

    final addonSections = AddonSectionRegistry.buildAvailableSections(context, game);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Dynamic Hero Header with Looping Microtrailer & Transparent Logo
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppTheme.surface,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: MicrotrailerPlayer(
                microtrailerDriveFileId: game.media.microtrailerDriveFileId,
                backgroundDriveFileId: game.media.backgroundDriveFileId,
                logoDriveFileId: game.media.logoDriveFileId,
                height: 250,
              ),
            ),
          ),

          // Content Body
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // Game Title & Company Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (developer != null || publisher != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [developer, publisher].whereType<String>().toSet().join(' • '),
                          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Metadata badges (Platform, Source, Genres, Status)
                MetadataChipsRow(game: game),

                // Playtime & Sessions Summary
                PlayTimeCard(game: game),

                // Description Card
                if (game.description != null && game.description!.trim().isNotEmpty)
                  _buildDescriptionCard(game.description!),

                // User Notes Card (if present)
                if (game.notes != null && game.notes!.trim().isNotEmpty)
                  _buildNotesCard(game.notes!),

                // External Hyperlinks
                ExternalLinksCard(links: game.links),

                // Dynamically Injected Polymorphic Addon Sections
                ...addonSections,

                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(String rawHtml) {
    // Strip simple HTML tags for clean text preview
    final plainText = rawHtml
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'About',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              plainText,
              maxLines: _isDescriptionExpanded ? null : 4,
              overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.45, color: AppTheme.textSecondary),
            ),
            if (plainText.length > 200)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
                  child: Text(
                    _isDescriptionExpanded ? 'Show less' : 'Read more',
                    style: const TextStyle(color: AppTheme.primaryLight, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(String notes) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notes, color: AppTheme.accentCyan, size: 18),
                SizedBox(width: 8),
                Text(
                  'My Notes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              notes,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
