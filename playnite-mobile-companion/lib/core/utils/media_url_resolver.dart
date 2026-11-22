import '../network/drive_api_service.dart';

/// Resolver for resolving Google Drive file IDs and media references to streaming/download URLs.
/// Delegates to the registered [DriveApiService] storage adapter if available.
class MediaUrlResolver {
  static DriveApiService? _activeStorage;
  static String? _legacyAuthToken;

  /// Registers the active DriveApiService storage adapter.
  static void setActiveStorage(DriveApiService? storage) {
    _activeStorage = storage;
  }

  /// Current active storage adapter.
  static DriveApiService? get activeStorage => _activeStorage;

  /// Sets the active Google OAuth2 Bearer token for media requests.
  static void setAuthToken(String? token) {
    _legacyAuthToken = token;
  }

  /// Current active token
  static String? get authToken => _legacyAuthToken;

  /// Returns direct media stream or download URL for given file ID or path.
  static String getDriveMediaStreamUrl(String driveFileId) {
    if (driveFileId.isEmpty) return '';
    if (_activeStorage != null) {
      return _activeStorage!.resolveMediaUri(driveFileId);
    }
    return _defaultResolveMediaUri(driveFileId);
  }

  /// Returns media URL for thumbnails and grid cards (routes to standard authenticated media stream).
  static String getDriveThumbnailUrl(String driveFileId, {int width = 400}) {
    return getDriveMediaStreamUrl(driveFileId);
  }

  /// Returns HTTP headers including Authorization if token is set or provided by active storage.
  static Map<String, String> getAuthHeaders({String? token, String? mediaUri}) {
    if (token != null && token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    if (_activeStorage != null) {
      return _activeStorage!.getMediaHeaders(mediaUri: mediaUri);
    }
    final active = _legacyAuthToken;
    if (active != null && active.isNotEmpty) {
      return {'Authorization': 'Bearer $active'};
    }
    return const {};
  }

  static String _defaultResolveMediaUri(String driveFileId) {
    if (driveFileId.startsWith('http://') ||
        driveFileId.startsWith('https://') ||
        driveFileId.startsWith('file://')) {
      return driveFileId;
    }
    if (driveFileId.startsWith('/') ||
        driveFileId.contains(':\\') ||
        driveFileId.contains(':/')) {
      return 'file://$driveFileId';
    }
    // Prevent invalid Drive API queries on un-resolved relative or legacy cache paths
    if (driveFileId.contains('\\') ||
        driveFileId.startsWith('icon_cache') ||
        driveFileId.startsWith('media/')) {
      return '';
    }
    return 'https://www.googleapis.com/drive/v3/files/$driveFileId?alt=media';
  }
}
