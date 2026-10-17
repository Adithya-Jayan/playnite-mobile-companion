import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../features/sync/domain/sync_models.dart';
import '../utils/media_url_resolver.dart';
import 'drive_api_service.dart';

/// Real Google Drive REST API service utilizing standard OAuth2 bearer tokens.
class GoogleDriveApiService implements DriveApiService {
  final http.Client client;
  final String syncFolderName;
  final String? clientId;
  final String? clientSecret;
  final String? refreshToken;
  final Future<void> Function(String newAccessToken)? onTokenRefreshed;
  String? _cachedSyncFolderId;

  GoogleDriveApiService({
    http.Client? client,
    this.syncFolderName = 'PlayniteSync',
    String? explicitFolderId,
    this.clientId,
    this.clientSecret,
    this.refreshToken,
    this.onTokenRefreshed,
  })  : client = client ?? http.Client(),
        _cachedSyncFolderId = (explicitFolderId != null && explicitFolderId.trim().isNotEmpty)
            ? explicitFolderId.trim()
            : null;

  Map<String, String> get _authHeaders => MediaUrlResolver.getAuthHeaders();

  /// Automatically requests a fresh OAuth access token using stored refresh token credentials
  Future<bool> refreshAccessToken() async {
    final rToken = refreshToken?.trim();
    final cId = clientId?.trim();
    if (rToken == null || rToken.isEmpty || cId == null || cId.isEmpty) {
      return false;
    }

    try {
      final tokenUri = Uri.parse('https://oauth2.googleapis.com/token');
      final body = {
        'grant_type': 'refresh_token',
        'client_id': cId,
        'refresh_token': rToken,
      };
      final cSecret = clientSecret?.trim();
      if (cSecret != null && cSecret.isNotEmpty) {
        body['client_secret'] = cSecret;
      }

      final res = await client.post(tokenUri, body: body);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String?;
        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          MediaUrlResolver.setAuthToken(newAccessToken);
          if (onTokenRefreshed != null) {
            await onTokenRefreshed!(newAccessToken);
          }
          return true;
        }
      }
    } catch (_) {
      // Refresh request failed
    }
    return false;
  }

  @override
  Future<SyncIndex> fetchSyncIndex() async {
    final fileId = await _findFileIdInFolder('sync_index.json');
    if (fileId == null) {
      throw StateError(
        'sync_index.json not found in Google Drive folder "$syncFolderName". '
        'Please run an export from Playnite desktop first.',
      );
    }
    final content = await downloadFileText(fileId);
    final json = jsonDecode(content) as Map<String, dynamic>;
    return SyncIndex.fromJson(json);
  }

  @override
  Future<String> downloadFileText(String fileIdOrPath) async {
    final url = MediaUrlResolver.getDriveMediaStreamUrl(fileIdOrPath);
    final uri = Uri.parse(url);

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        var response = await client
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 401 && await refreshAccessToken()) {
          response = await client
              .get(uri, headers: _authHeaders)
              .timeout(const Duration(seconds: 30));
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return utf8.decode(response.bodyBytes);
        } else if (response.statusCode == 401) {
          throw StateError('Google Drive Authorization Expired (HTTP 401). Please re-authenticate in Settings.');
        } else if (response.statusCode == 429 || response.statusCode >= 500) {
          if (attempt == maxRetries) {
            throw StateError('Google Drive error HTTP ${response.statusCode} for "$fileIdOrPath" after $maxRetries attempts.');
          }
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        } else {
          throw StateError('Failed to download file "$fileIdOrPath": HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (attempt == maxRetries) {
          rethrow;
        }
        debugPrint('Download attempt $attempt failed for $fileIdOrPath: $e. Retrying in ${600 * attempt}ms...');
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
    throw StateError('Download failed for "$fileIdOrPath" after $maxRetries attempts.');
  }

  @override
  Future<Map<String, dynamic>> fetchManifest({String? fileId}) async {
    final id = fileId ?? await _findFileIdInFolder('manifest.json');
    if (id == null) return {};
    final content = await downloadFileText(id);
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Verifies OAuth token validity and Google Drive folder availability
  Future<Map<String, dynamic>> testConnection() async {
    var headers = _authHeaders;
    if (!headers.containsKey('Authorization')) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        headers = _authHeaders;
      } else {
        return {
          'success': false,
          'error': 'No active Google Drive access token configured. Please link via Playnite Desktop Pairing Code or sign in.',
        };
      }
    }

    try {
      // 1. Verify user identity
      final userUri = Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user(displayName,emailAddress)');
      var userRes = await client.get(userUri, headers: headers);

      if (userRes.statusCode == 401 && await refreshAccessToken()) {
        headers = _authHeaders;
        userRes = await client.get(userUri, headers: headers);
      }

      if (userRes.statusCode == 401) {
        return {
          'success': false,
          'error': '401 Unauthorized: Access token is expired or invalid. Note: A Google Client ID is an application identifier, not an access token. Tap "Link via Playnite Desktop Pairing" to connect permanently!',
        };
      }
      if (userRes.statusCode != 200) {
        return {
          'success': false,
          'error': 'Google Drive API error: HTTP ${userRes.statusCode}',
        };
      }
      final userData = jsonDecode(userRes.body) as Map<String, dynamic>;
      final user = userData['user'] as Map<String, dynamic>?;
      final email = user?['emailAddress'] as String? ?? 'Authenticated User';

      // 2. Locate sync folder
      final folderId = await _getFolderId();
      if (folderId == null) {
        return {
          'success': false,
          'user': email,
          'error': 'Folder "$syncFolderName" not found in Drive. Run sync from Playnite desktop first.',
        };
      }

      // 3. Inspect items in folder
      final filesUri = Uri.parse(
        "https://www.googleapis.com/drive/v3/files?q='$folderId'+in+parents+and+trashed=false&fields=files(id,name)",
      );
      var filesRes = await client.get(filesUri, headers: headers);
      if (filesRes.statusCode == 401 && await refreshAccessToken()) {
        headers = _authHeaders;
        filesRes = await client.get(filesUri, headers: headers);
      }

      var fileCount = 0;
      bool hasIndex = false;
      if (filesRes.statusCode == 200) {
        final fData = jsonDecode(filesRes.body) as Map<String, dynamic>;
        final list = fData['files'] as List?;
        fileCount = list?.length ?? 0;
        hasIndex = list?.any((f) => f['name'] == 'sync_index.json') ?? false;
      }

      return {
        'success': true,
        'user': email,
        'folderId': folderId,
        'fileCount': fileCount,
        'hasIndex': hasIndex,
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection test failed: $e'};
    }
  }

  Future<String?> _findFileIdInFolder(String fileName) async {
    final folderId = await _getFolderId();
    if (folderId == null) return null;

    final query = "name = '$fileName' and '$folderId' in parents and trashed = false";
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(query)}&fields=files(id,name)',
    );

    var response = await client.get(uri, headers: _authHeaders);
    if (response.statusCode == 401 && await refreshAccessToken()) {
      response = await client.get(uri, headers: _authHeaders);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final files = data['files'] as List?;
      if (files != null && files.isNotEmpty) {
        return files.first['id'] as String?;
      }
    }
    return null;
  }

  Future<String?> _getFolderId() async {
    if (_cachedSyncFolderId != null) return _cachedSyncFolderId;
    final query = "name = '$syncFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=${Uri.encodeComponent(query)}&fields=files(id,name)',
    );

    var response = await client.get(uri, headers: _authHeaders);
    if (response.statusCode == 401 && await refreshAccessToken()) {
      response = await client.get(uri, headers: _authHeaders);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final files = data['files'] as List?;
      if (files != null && files.isNotEmpty) {
        _cachedSyncFolderId = files.first['id'] as String?;
        return _cachedSyncFolderId;
      }
    }
    return null;
  }
}
