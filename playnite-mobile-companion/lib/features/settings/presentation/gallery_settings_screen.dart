import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/widgets/sync_dialog.dart';

class GallerySettingsScreen extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback? onSettingsChanged;

  const GallerySettingsScreen({
    super.key,
    required this.database,
    this.onSettingsChanged,
  });

  @override
  State<GallerySettingsScreen> createState() => _GallerySettingsScreenState();
}

class _GallerySettingsScreenState extends State<GallerySettingsScreen> {
  late final GallerySettingsRepository _repo;
  GallerySettings _settings = const GallerySettings();
  MediaTierSizes _tierSizes = const MediaTierSizes();
  bool _isLoading = true;
  int _cachedCount = 0;
  int _cachedBytes = 0;

  @override
  void initState() {
    super.initState();
    _repo = GallerySettingsRepository(widget.database);
    _loadSettings();
    _loadCacheMetrics();
  }

  Future<void> _loadSettings() async {
    final s = await _repo.loadSettings();
    final sizes = await _repo.loadMediaTierSizes();
    if (mounted) {
      setState(() {
        _settings = s;
        _tierSizes = sizes;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCacheMetrics() async {
    final count = PlayniteImageLoader.instance.cachedImagesCount;
    final bytes = await PlayniteImageLoader.instance.getCacheSizeBytes();
    if (mounted) {
      setState(() {
        _cachedCount = count;
        _cachedBytes = bytes;
      });
    }
  }

  Future<void> _updateSettings(GallerySettings newSettings) async {
    final oldTier = _settings.mediaStorageTier;
    final newTier = newSettings.mediaStorageTier;

    setState(() => _settings = newSettings);
    await _repo.saveSettings(newSettings);
    widget.onSettingsChanged?.call();

    // Check tier transitions
    if (oldTier != newTier) {
      if (newTier == MediaStorageTier.cacheOnly && oldTier != MediaStorageTier.cacheOnly) {
        // Ask the user before deleting previously downloaded media
        if (mounted) {
          await _promptClearCacheOnDowngrade();
        }
      } else if (newTier.index > oldTier.index) {
        // Upgraded to an offline storage tier: Prompt user to run sync
        if (mounted) {
          _promptSyncForOfflineMedia(newTier);
        }
      }
    }
  }

  Future<void> _promptClearCacheOnDowngrade() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: AppTheme.primaryLight),
            SizedBox(width: 8),
            Text('Free Up Storage Space?'),
          ],
        ),
        content: const Text(
          'You switched your storage tier back to "Cache Only".\n\n'
          'Would you like to delete previously downloaded offline media to free up device space now, or keep them locally cached?\n\n'
          '(You can always clear downloaded media at any time using the "Clear Media Cache" button below).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Downloaded Media', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear & Free Up Space', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      await PlayniteImageLoader.instance.clearCache();
      await _loadCacheMetrics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline media cleaned up to save local storage.'),
            backgroundColor: AppTheme.accentGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getCoversAndFanartsSizeLabel() {
    if (_tierSizes.coversAndFanartsBytes != null && _tierSizes.coversAndFanartsBytes! > 0) {
      return '~${DurationFormatter.formatBytes(_tierSizes.coversAndFanartsBytes!)}';
    }
    return '~1.28 GB est.';
  }

  String _getCompleteOfflineSizeLabel() {
    if (_tierSizes.completeOfflineBytes != null && _tierSizes.completeOfflineBytes! > 0) {
      return '~${DurationFormatter.formatBytes(_tierSizes.completeOfflineBytes!)}';
    }
    return '~3.5 GB est.';
  }

  void _promptSyncForOfflineMedia(MediaStorageTier tier) {
    final label = tier == MediaStorageTier.completeOffline
        ? 'Complete Offline with Videos (${_getCompleteOfflineSizeLabel()})'
        : 'Full Offline Covers & Fanarts (${_getCoversAndFanartsSizeLabel()})';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Row(
          children: [
            Icon(Icons.cloud_download, color: AppTheme.primaryLight),
            SizedBox(width: 8),
            Text('Pre-download Media?'),
          ],
        ),
        content: Text(
          'You enabled "$label".\n\n'
          'Would you like to run a Sync now to pre-download all game media for offline browsing?',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.of(ctx).pop();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => SyncDialog(database: widget.database),
              ).then((_) {
                _loadCacheMetrics();
                _loadSettings();
              });
            },
            child: const Text('Sync Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _getScoreSourceSubtitle(RatingScoreSource source) {
    switch (source) {
      case RatingScoreSource.community:
        return 'Public / Community Score (Steam, IGDB) - Recommended default';
      case RatingScoreSource.composite:
        return 'Composite (Best Available: user, critic, community)';
      case RatingScoreSource.critic:
        return 'Critic Score (Metacritic, OpenCritic)';
      case RatingScoreSource.user:
        return 'User Score (Personal library rating)';
    }
  }

  String _getMediaStorageTierSubtitle(MediaStorageTier tier) {
    switch (tier) {
      case MediaStorageTier.cacheOnly:
        return 'Cache Only (On-demand as you browse library - Default)';
      case MediaStorageTier.coversAndFanarts:
        return 'Full Offline Covers & Fanarts (${_getCoversAndFanartsSizeLabel()})';
      case MediaStorageTier.completeOffline:
        return 'Complete Offline with Videos (${_getCompleteOfflineSizeLabel()})';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gallery Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Visibility & Privacy Section
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Visibility & Privacy',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          title: const Text(
                            'Show Hidden Games',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Display hidden games in your library. When toggled off, hidden games are completely excluded from the normal gallery.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          activeThumbColor: AppTheme.primary,
                          value: _settings.showHiddenGames,
                          onChanged: (val) {
                            _updateSettings(_settings.copyWith(showHiddenGames: val));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Display Preferences Section
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Display Preferences',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text(
                            'Default View Mode',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            _settings.defaultViewMode == 'grid'
                                ? 'Grid (Covers)'
                                : (_settings.defaultViewMode == 'list' ? 'List View' : 'Details View'),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          trailing: DropdownButton<String>(
                            value: _settings.defaultViewMode,
                            dropdownColor: AppTheme.surfaceLight,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(value: 'grid', child: Text('Grid')),
                              DropdownMenuItem(value: 'list', child: Text('List')),
                              DropdownMenuItem(value: 'details', child: Text('Details')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                _updateSettings(_settings.copyWith(defaultViewMode: val));
                              }
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text(
                            'Rating Score Source',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            _getScoreSourceSubtitle(_settings.ratingScoreSource),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          trailing: DropdownButton<RatingScoreSource>(
                            value: _settings.ratingScoreSource,
                            dropdownColor: AppTheme.surfaceLight,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: RatingScoreSource.community,
                                child: Text('Public / Community Score'),
                              ),
                              DropdownMenuItem(
                                value: RatingScoreSource.composite,
                                child: Text('Composite (Best Available)'),
                              ),
                              DropdownMenuItem(
                                value: RatingScoreSource.critic,
                                child: Text('Critic Score (Metacritic)'),
                              ),
                              DropdownMenuItem(
                                value: RatingScoreSource.user,
                                child: Text('Personal User Score'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                _updateSettings(_settings.copyWith(ratingScoreSource: val));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Media Storage & Offline Sync Section
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Media Storage & Offline Sync',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        ListTile(
                          title: const Text(
                            'Media Storage Mode',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            _getMediaStorageTierSubtitle(_settings.mediaStorageTier),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          trailing: DropdownButton<MediaStorageTier>(
                            value: _settings.mediaStorageTier,
                            dropdownColor: AppTheme.surfaceLight,
                            underline: const SizedBox.shrink(),
                            items: [
                              const DropdownMenuItem(
                                value: MediaStorageTier.cacheOnly,
                                child: Text('Cache Only (On-demand)'),
                              ),
                              DropdownMenuItem(
                                value: MediaStorageTier.coversAndFanarts,
                                child: Text('Covers & Fanarts (${_getCoversAndFanartsSizeLabel()})'),
                              ),
                              DropdownMenuItem(
                                value: MediaStorageTier.completeOffline,
                                child: Text('Full with Videos (${_getCompleteOfflineSizeLabel()})'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                _updateSettings(_settings.copyWith(mediaStorageTier: val));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Microtrailer Video Controls Section
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'Microtrailer Video Settings',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Auto-play Microtrailers', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                          subtitle: const Text('Loop 6-second video headers automatically in detail view', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          value: _settings.autoPlayMicrotrailers,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (v) => _updateSettings(_settings.copyWith(autoPlayMicrotrailers: v)),
                        ),
                        SwitchListTile(
                          title: const Text('Start Muted by Default', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                          subtitle: const Text('Play trailers silently until unmuted via overlay control', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          value: _settings.microtrailerMuted,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (v) => _updateSettings(_settings.copyWith(microtrailerMuted: v)),
                        ),
                        SwitchListTile(
                          title: const Text('Show Video Scrub Bar', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                          subtitle: const Text('Display progress scrubber with timestamps in overlay', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          value: _settings.showVideoScrubBar,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (v) => _updateSettings(_settings.copyWith(showVideoScrubBar: v)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Storage & Cache Management Card
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cleaning_services_outlined, color: AppTheme.primaryLight, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Storage & Cache Management',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cached Files: $_cachedCount images',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Disk Usage: ${DurationFormatter.formatBytes(_cachedBytes)}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.surfaceLight,
                                foregroundColor: AppTheme.accentRed,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Clear Cache'),
                              onPressed: () async {
                                await PlayniteImageLoader.instance.clearCache();
                                await _loadCacheMetrics();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Image cache cleared successfully.'),
                                      backgroundColor: AppTheme.accentGreen,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
