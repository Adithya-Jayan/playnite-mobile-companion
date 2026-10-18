import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/settings/presentation/gallery_settings_screen.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  final AppDatabase database;
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.database,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section: Gallery & Library
          _buildSectionHeader('Preferences'),
          Card(
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: AppTheme.primaryLight, size: 20),
                  ),
                  title: const Text(
                    'Gallery & Display',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Show hidden games, default view mode',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GallerySettingsScreen(
                          database: database,
                          onSettingsChanged: onSettingsChanged,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section: Cloud & Sync
          _buildSectionHeader('Cloud & Storage'),
          Card(
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_sync_outlined, color: Colors.blueAccent, size: 20),
                  ),
                  title: const Text(
                    'Google Drive & Sync',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Google Drive account, storage mode, background sync & battery',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SyncSettingsScreen(
                          database: database,
                          onSettingsChanged: onSettingsChanged,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section: About
          _buildSectionHeader('About'),
          Card(
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 20),
                  ),
                  title: const Text(
                    'Playnite Companion',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Version 1.1.0 • Delta Sync Protocol',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: AppTheme.primaryLight,
        ),
      ),
    );
  }
}
