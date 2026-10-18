import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/ui/playnite_cached_image.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
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
  DuplicateCopyPayload? _selectedCopy;
  late Map<String, dynamic> _addons;
  List<UnifiedGamePayload> _relatedGames = [];

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _addons = widget.game.addons;
    if (_addons.isEmpty) {
      _loadAddons();
    }
    // Defer related games to next frame so hero background & primary game details render instantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadRelatedGames();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isTesting) return;
    final bgId = widget.game.media.backgroundDriveFileId;
    if (bgId != null && bgId.isNotEmpty) {
      final isDirectHttp = bgId.startsWith('http://') || bgId.startsWith('https://');
      final streamUrl = isDirectHttp ? bgId : MediaUrlResolver.getDriveMediaStreamUrl(bgId);
      final headers = (isDirectHttp && !streamUrl.contains('googleapis.com'))
          ? <String, String>{}
          : MediaUrlResolver.getAuthHeaders();
      precacheImage(NetworkImage(streamUrl, headers: headers), context).catchError((_) {});
    }
  }

  Future<void> _loadAddons() async {
    try {
      if (AppDatabase.instance.isOpen) {
        final dao = GameDao(AppDatabase.instance);
        final loaded = await dao.getGameAddons(widget.game.id);
        if (mounted && loaded.isNotEmpty) {
          setState(() => _addons = loaded);
        }
      }
    } catch (e) {
      debugPrint('Error loading addons on demand: $e');
    }
  }

  Future<void> _loadRelatedGames() async {
    try {
      if (AppDatabase.instance.isOpen) {
        final dao = GameDao(AppDatabase.instance);
        final related = await dao.getRelatedGames(
          currentGameId: widget.game.id,
          series: widget.game.series,
          developers: widget.game.developers,
        );
        if (mounted && related.isNotEmpty) {
          setState(() => _relatedGames = related);
        }
      }
    } catch (e) {
      debugPrint('Error loading related games: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _addons.isNotEmpty ? widget.game.copyWith(addons: _addons) : widget.game;
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
                trailerDriveFileId: game.media.trailerDriveFileId,
                trailerWebUrl: game.media.trailerWebUrl,
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

                // Multi-Store copies switcher (DuplicateHider)
                if (game.otherCopies.isNotEmpty) _buildStoreCopiesSwitcher(game),

                // Playtime & Sessions Summary
                PlayTimeCard(game: game),

                // Description Card
                if (game.description != null && game.description!.trim().isNotEmpty)
                  _buildDescriptionCard(game.description!),

                // Related Games (Same Series / Developer)
                _buildRelatedGamesCard(game),

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

  Widget _buildRelatedGamesCard(UnifiedGamePayload currentGame) {
    if (_relatedGames.isEmpty) return const SizedBox.shrink();

    final hasSeries = currentGame.series.isNotEmpty;
    final seriesName = hasSeries ? currentGame.series.first.name : null;
    final devName = currentGame.developers.isNotEmpty ? currentGame.developers.first.name : null;

    final String title;
    if (seriesName != null && devName != null) {
      title = 'More in $seriesName & by $devName';
    } else if (seriesName != null) {
      title = 'More in $seriesName';
    } else if (devName != null) {
      title = 'More by $devName';
    } else {
      title = 'Related Games';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_motion, color: AppTheme.primaryLight, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _relatedGames.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final related = _relatedGames[index];
                  return GestureDetector(
                    onTap: () {
                      final bgId = related.media.backgroundDriveFileId;
                      if (bgId != null && bgId.isNotEmpty) {
                        final isDirectHttp = bgId.startsWith('http://') || bgId.startsWith('https://');
                        final streamUrl = isDirectHttp ? bgId : MediaUrlResolver.getDriveMediaStreamUrl(bgId);
                        final headers = (isDirectHttp && !streamUrl.contains('googleapis.com'))
                            ? <String, String>{}
                            : MediaUrlResolver.getAuthHeaders();
                        precacheImage(NetworkImage(streamUrl, headers: headers), context).catchError((_) {});
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => GameDetailScreen(game: related)),
                      );
                    },
                    child: SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 88,
                              height: 115,
                              child: PlayniteCachedImage(
                                mediaId: related.media.coverDriveFileId,
                                fit: BoxFit.cover,
                                memCacheWidth: 180,
                                memCacheHeight: 240,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            related.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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

  Widget _buildStoreCopiesSwitcher(UnifiedGamePayload game) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copy_all, size: 16, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                const Text(
                  'Multi-Store Copies (DuplicateHider)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const Spacer(),
                Text(
                  '${game.otherCopies.length + 1} stores owned',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Primary / Default Copy
                ChoiceChip(
                  label: Text('${game.source?.name ?? "Primary"}${game.isInstalled ? " (Installed)" : ""}'),
                  selected: _selectedCopy == null,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCopy = null);
                  },
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _selectedCopy == null ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
                // Alternate Copies
                ...game.otherCopies.map((copy) {
                  final isSelected = _selectedCopy?.id == copy.id;
                  return ChoiceChip(
                    label: Text('${copy.sourceName}${copy.isInstalled ? " (Installed)" : ""}'),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedCopy = selected ? copy : null);
                    },
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                    ),
                  );
                }),
              ],
            ),
            if (_selectedCopy != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Store: ${_selectedCopy!.sourceName}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Playtime: ${DurationFormatter.formatSecondsToHoursMinutes(_selectedCopy!.playtimeSeconds)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _selectedCopy!.isInstalled ? AppTheme.accentGreen.withValues(alpha: 0.2) : Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _selectedCopy!.isInstalled ? 'Installed' : 'Cloud Library',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _selectedCopy!.isInstalled ? AppTheme.accentGreen : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
