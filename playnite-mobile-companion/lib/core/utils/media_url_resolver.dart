/// Resolver for resolving Google Drive file IDs and media references to streaming/download URLs.
class MediaUrlResolver {
  static String? _authToken;

  /// Sets the active Google OAuth2 Bearer token for media requests.
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Current active token
  static String? get authToken => _authToken;

  /// Returns direct Google Drive download/stream URL for given file ID.
  static String getDriveMediaStreamUrl(String driveFileId) {
    if (driveFileId.startsWith('http://') || driveFileId.startsWith('https://')) {
      return driveFileId;
    }
    return 'https://www.googleapis.com/drive/v3/files/$driveFileId?alt=media';
  }

  /// Returns Google Drive thumbnail URL.
  static String getDriveThumbnailUrl(String driveFileId, {int width = 400}) {
    if (driveFileId.startsWith('http://') || driveFileId.startsWith('https://')) {
      return driveFileId;
    }
    return 'https://drive.google.com/thumbnail?id=$driveFileId&sz=w$width';
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
