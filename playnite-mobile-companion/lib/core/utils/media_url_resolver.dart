/// Resolver for resolving Google Drive file IDs and media references to streaming/download URLs.
class MediaUrlResolver {
  static String? _authToken;

  /// Sets the active Google OAuth2 Bearer token for media requests.
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Current active token
  static String? get authToken => _authToken;

  /// Returns direct Google Drive download/stream URL for given file ID or direct URL.
  static String getDriveMediaStreamUrl(String driveFileId) {
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
    return 'https://www.googleapis.com/drive/v3/files/$driveFileId?alt=media';
  }

  /// Returns media URL for thumbnails and grid cards (routes to standard authenticated media stream).
  static String getDriveThumbnailUrl(String driveFileId, {int width = 400}) {
    return getDriveMediaStreamUrl(driveFileId);
  }

  /// Returns HTTP headers including Authorization if token is set.
  static Map<String, String> getAuthHeaders({String? token}) {
    final active = token ?? _authToken;
    if (active != null && active.isNotEmpty) {
      return {'Authorization': 'Bearer $active'};
    }
    return const {};
  }
}
