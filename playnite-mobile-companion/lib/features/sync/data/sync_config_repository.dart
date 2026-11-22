import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/network/drive_api_service.dart';
import 'package:playnite_mobile_companion/core/network/google_drive_api_service.dart';
import 'package:playnite_mobile_companion/core/network/local_folder_drive_service.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/sync/data/demo_library_data.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite/sqflite.dart';

/// Repository for persisting and managing the active synchronization configuration and provider.
class SyncConfigRepository {
  final AppDatabase database;
  static const String _configKey = 'sync_config';

  SyncConfigRepository(this.database);

  /// Loads stored configuration from SQLite or returns default settings
  Future<SyncConfiguration> loadConfig() async {
    try {
      final results = await database.db.query(
        'manifest_meta',
        where: 'key = ?',
        whereArgs: [_configKey],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final jsonText = results.first['value_json'] as String;
        final json = jsonDecode(jsonText) as Map<String, dynamic>;
        final config = SyncConfiguration.fromJson(json);

        // Synchronize active auth token and active storage adapter with MediaUrlResolver
        if (config.googleAccessToken.isNotEmpty) {
          MediaUrlResolver.setAuthToken(config.googleAccessToken);
        } else {
          MediaUrlResolver.setAuthToken(null);
        }
        createDriveService(config);
        return config;
      }
    } catch (e) {
      debugPrint('Error loading sync config: $e');
    }

    return const SyncConfiguration();
  }

  /// Persists updated configuration into SQLite
  Future<void> saveConfig(SyncConfiguration config) async {
    try {
      await database.db.insert(
        'manifest_meta',
        {
          'key': _configKey,
          'value_json': jsonEncode(config.toJson()),
          'updated_utc': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update active auth token
      if (config.googleAccessToken.isNotEmpty) {
        MediaUrlResolver.setAuthToken(config.googleAccessToken);
      } else {
        MediaUrlResolver.setAuthToken(null);
      }
    } catch (e) {
      debugPrint('Error saving sync config: $e');
      rethrow;
    }
  }

  /// Instantiates the appropriate DriveApiService based on active configuration
  DriveApiService createDriveService(SyncConfiguration config) {
    final DriveApiService service;
    switch (config.storageType) {
      case SyncStorageType.googleDrive:
        service = GoogleDriveApiService(
          accessToken: config.googleAccessToken.isNotEmpty ? config.googleAccessToken : null,
          syncFolderName: config.googleDriveFolderName.isNotEmpty ? config.googleDriveFolderName : 'PlayniteSync',
          explicitFolderId: config.googleDriveFolderId.isNotEmpty ? config.googleDriveFolderId : null,
          clientId: config.googleClientId,
          clientSecret: config.googleClientSecret,
          refreshToken: config.googleRefreshToken,
          onTokenRefreshed: (newAccessToken) async {
            final latest = (await loadConfig()).copyWith(googleAccessToken: newAccessToken);
            await saveConfig(latest);
          },
        );
        break;

      case SyncStorageType.localFolder:
        service = LocalFolderDriveService(config.localFolderPath);
        break;

      case SyncStorageType.demo:
        service = DemoLibraryData.createDemoDriveService();
        break;
    }

    MediaUrlResolver.setActiveStorage(service);
    return service;
  }
}
