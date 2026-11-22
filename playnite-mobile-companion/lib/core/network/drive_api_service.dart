import '../../features/sync/domain/sync_models.dart';

/// Structured validation result when checking storage connectivity, permissions, and readiness.
class StorageValidationResult {
  final bool isValid;
  final String message;
  final bool permissionDenied;
  final bool requiresAuth;
  final int? totalGames;
  final Map<String, dynamic> details;

  const StorageValidationResult({
    required this.isValid,
    required this.message,
    this.permissionDenied = false,
    this.requiresAuth = false,
    this.totalGames,
    this.details = const {},
  });

  const StorageValidationResult.success({
    required this.message,
    this.totalGames,
    this.details = const {},
  })  : isValid = true,
        permissionDenied = false,
        requiresAuth = false;

  const StorageValidationResult.failure({
    required this.message,
    this.permissionDenied = false,
    this.requiresAuth = false,
    this.totalGames,
    this.details = const {},
  }) : isValid = false;
}

/// Abstract deep service interface for remote and local storage adapters at the Storage Seam.
abstract class DriveApiService {
  /// Fetches and parses remote sync_index.json
  Future<SyncIndex> fetchSyncIndex();

  /// Downloads text content (JSON) for a given drive file ID or relative path
  Future<String> downloadFileText(String fileIdOrPath);

  /// Downloads binary bytes for a given drive file ID or relative path
  Future<List<int>> downloadFileBytes(String fileIdOrPath);

  /// Downloads manifest.json dictionary
  Future<Map<String, dynamic>> fetchManifest({String? fileId});

  /// Verifies storage connectivity, directory/folder availability, and permissions.
  Future<StorageValidationResult> verifyConnection();

  /// Requests any required platform permissions for this storage provider (e.g. Android All Files Access).
  /// Returns true if granted or not needed.
  Future<bool> requestPermissions() async => true;

  /// Refreshes credentials/tokens if applicable to this storage provider.
  /// Returns true if refreshed successfully or not applicable.
  Future<bool> refreshAuth() async => false;

  /// Resolves a media file identifier (hash, CAS path, drive ID) into a streaming or local URI.
  String resolveMediaUri(String mediaIdOrPath);

  /// Returns authentication or custom HTTP headers required when streaming media from this provider.
  Map<String, String> getMediaHeaders({String? mediaUri}) => const {};
}
