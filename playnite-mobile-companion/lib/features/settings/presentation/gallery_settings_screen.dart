import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/core/utils/duration_formatter.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';

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
    if (mounted) {
      setState(() {
        _settings = s;
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
    setState(() => _settings = newSettings);
    await _repo.saveSettings(newSettings);
    try {
      final syncRepo = SyncConfigRepository(widget.database);
      final syncConfig = await syncRepo.loadConfig();
      if (syncConfig.autoStreamTrailersInHero != newSettings.autoStreamTrailersInHero) {
        await syncRepo.saveConfig(syncConfig.copyWith(autoStreamTrailersInHero: newSettings.autoStreamTrailersInHero));
      }
    } catch (_) {}
    widget.onSettingsChanged?.call();
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

    Widget _buildVideoPrioritySection() {
    return Card(
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
                'Video Playback & Fallback Priority',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryLight,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Drag to adjust playback preference. Top-most available source plays first.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
            const Divider(height: 1),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _settings.videoPlaybackPriority.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final updated = List<VideoSourceType>.from(_settings.videoPlaybackPriority);
                final item = updated.removeAt(oldIndex);
                updated.insert(newIndex, item);
                _updateSettings(_settings.copyWith(videoPlaybackPriority: updated));
              },
              itemBuilder: (context, index) {
                final source = _settings.videoPlaybackPriority[index];
                return _buildPriorityTile(source, index);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityTile(VideoSourceType source, int index) {
    final String title;
    final String subtitle;
    final bool isEnabled;
    final ValueChanged<bool> onToggle;

    switch (source) {
      case VideoSourceType.miniTrailer:
        title = 'MiniTrailer (Microtrailer)';
        subtitle = '6-second looping microtrailer (cached offline)';
        isEnabled = _settings.enableMiniTrailers;
        onToggle = (val) => _updateSettings(_settings.copyWith(enableMiniTrailers: val));
        break;
      case VideoSourceType.hqVideo:
        title = 'HQ Video (Full Trailer)';
        subtitle = 'High-definition trailer from local cache / Drive';
        isEnabled = _settings.enableHqVideos;
        onToggle = (val) => _updateSettings(_settings.copyWith(enableHqVideos: val));
        break;
      case VideoSourceType.onlineStream:
        title = 'Online Stream (Steam CDN)';
        subtitle = 'Stream directly from Steam over network (uses data)';
        isEnabled = _settings.enableOnlineStream;
        onToggle = (val) => _updateSettings(_settings.copyWith(enableOnlineStream: val));
        break;
    }

    return ListTile(
      key: ValueKey(source),
      leading: ReorderableDragStartListener(
        index: index,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: const Icon(Icons.drag_handle, color: AppTheme.textMuted),
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
      ),
      trailing: Switch(
        key: Key('switch_${source.name}'),
        value: isEnabled,
        activeThumbColor: AppTheme.primary,
        onChanged: onToggle,
      ),
    );
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
                            'Include User Hidden Games',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Show games you have manually marked as hidden in Playnite in your main gallery.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          activeThumbColor: AppTheme.primary,
                          value: _settings.includeUserHiddenGames,
                          onChanged: (val) {
                            _updateSettings(_settings.copyWith(includeUserHiddenGames: val));
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text(
                            'Include DuplicateHider Copies',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Show secondary duplicate copies suppressed by DuplicateHider in your main gallery.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          activeThumbColor: AppTheme.primary,
                          value: _settings.includeDuplicateHiderGames,
                          onChanged: (val) {
                            _updateSettings(_settings.copyWith(includeDuplicateHiderGames: val));
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

                // Media Storage & Offline Sync (Configured in Sync Settings)
                Card(
                  color: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.sync_outlined, color: AppTheme.primaryLight),
                    title: const Text(
                      'Media Storage & Offline Sync',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    subtitle: const Text(
                      'Media download policy is configured in Sync & Storage Settings',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SyncSettingsScreen(
                            database: widget.database,
                            onSettingsChanged: () {
                              _loadSettings();
                              widget.onSettingsChanged?.call();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                _buildVideoPrioritySection(),
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
                        SwitchListTile(
                          title: const Text('Auto-stream Full Trailers in Hero', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                          subtitle: const Text('Stream heavy full trailers automatically when microtrailers are unavailable (uses data)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          value: _settings.autoStreamTrailersInHero,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (v) => _updateSettings(_settings.copyWith(autoStreamTrailersInHero: v)),
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
