import '../../features/sync/domain/sync_models.dart';

/// Abstract service interface for Google Drive / remote storage interactions.
abstract class DriveApiService {
  /// Fetches and parses remote sync_index.json
  Future<SyncIndex> fetchSyncIndex();

  /// Downloads text content (JSON) for a given drive file ID or relative path
  Future<String> downloadFileText(String fileIdOrPath);

  /// Downloads binary bytes for a given drive file ID or relative path
  Future<List<int>> downloadFileBytes(String fileIdOrPath);

  /// Downloads manifest.json dictionary
  Future<Map<String, dynamic>> fetchManifest({String? fileId});
}
