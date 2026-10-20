import 'sync_models.dart';

export 'sync_models.dart' show SyncStorageType;

/// Configuration settings for sync operations and media streaming preferences.
class SyncConfiguration {
  final SyncStorageType storageType;
  final String googleDriveFolderName;
  final String googleDriveFolderId;
  final String googleClientId;
  final String googleClientSecret;
  final String googleRefreshToken;
  final String googleAccessToken;
  final String localFolderPath;
  final String? lastSyncUtc;
  final bool autoStreamTrailersInHero;

  const SyncConfiguration({
    this.storageType = SyncStorageType.googleDrive,
    this.googleDriveFolderName = 'PlayniteSync',
    this.googleDriveFolderId = '',
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.googleRefreshToken = '',
    this.googleAccessToken = '',
    this.localFolderPath = '',
    this.lastSyncUtc,
    this.autoStreamTrailersInHero = false,
  });

  bool get isGoogleDriveConfigured =>
      storageType == SyncStorageType.googleDrive &&
      (googleAccessToken.isNotEmpty || googleRefreshToken.isNotEmpty);

  SyncConfiguration copyWith({
    SyncStorageType? storageType,
    String? googleDriveFolderName,
    String? googleDriveFolderId,
    String? googleClientId,
    String? googleClientSecret,
    String? googleRefreshToken,
    String? googleAccessToken,
    String? localFolderPath,
    String? lastSyncUtc,
    bool? autoStreamTrailersInHero,
  }) {
    return SyncConfiguration(
      storageType: storageType ?? this.storageType,
      googleDriveFolderName: googleDriveFolderName ?? this.googleDriveFolderName,
      googleDriveFolderId: googleDriveFolderId ?? this.googleDriveFolderId,
      googleClientId: googleClientId ?? this.googleClientId,
      googleClientSecret: googleClientSecret ?? this.googleClientSecret,
      googleRefreshToken: googleRefreshToken ?? this.googleRefreshToken,
      googleAccessToken: googleAccessToken ?? this.googleAccessToken,
      localFolderPath: localFolderPath ?? this.localFolderPath,
      lastSyncUtc: lastSyncUtc ?? this.lastSyncUtc,
      autoStreamTrailersInHero: autoStreamTrailersInHero ?? this.autoStreamTrailersInHero,
    );
  }

  Map<String, dynamic> toJson() => {
    'storage_type': storageType.name,
    'google_drive_folder_name': googleDriveFolderName,
    'google_drive_folder_id': googleDriveFolderId,
    'google_client_id': googleClientId,
    'google_client_secret': googleClientSecret,
    'google_refresh_token': googleRefreshToken,
    'google_access_token': googleAccessToken,
    'local_folder_path': localFolderPath,
    'last_sync_utc': lastSyncUtc,
    'auto_stream_trailers_in_hero': autoStreamTrailersInHero,
  };

  factory SyncConfiguration.fromJson(Map<String, dynamic> json) {
    SyncStorageType type = SyncStorageType.googleDrive;
    final typeStr = json['storage_type'] as String?;
    if (typeStr != null) {
      for (final t in SyncStorageType.values) {
        if (t.name == typeStr) {
          type = t;
          break;
        }
      }
    }

    bool parseBool(dynamic val) {
      if (val is bool) return val;
      if (val is num) return val != 0;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      return false;
    }

    return SyncConfiguration(
      storageType: type,
      googleDriveFolderName: json['google_drive_folder_name'] as String? ?? 'PlayniteSync',
      googleDriveFolderId: json['google_drive_folder_id'] as String? ?? '',
      googleClientId: json['google_client_id'] as String? ?? '',
      googleClientSecret: json['google_client_secret'] as String? ?? '',
      googleRefreshToken: json['google_refresh_token'] as String? ?? '',
      googleAccessToken: json['google_access_token'] as String? ?? '',
      localFolderPath: json['local_folder_path'] as String? ?? '',
      lastSyncUtc: json['last_sync_utc'] as String?,
      autoStreamTrailersInHero: parseBool(json['auto_stream_trailers_in_hero'] ?? json['autoStreamTrailersInHero']),
    );
  }
}

/// Convenience alias matching Ticket #3 specification
typedef SyncConfig = SyncConfiguration;
