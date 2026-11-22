import 'dart:convert';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'drive_api_service.dart';

/// In-memory mock Drive service for unit tests and local simulations.
/// Tracks request counters to verify strict incremental network transfers.
class MockDriveService implements DriveApiService {
  SyncIndex? mockIndex;
  final Map<String, String> mockFiles = {};
  final Map<String, List<int>> mockBinaryFiles = {};

  int totalGetRequests = 0;
  int gamePayloadRequests = 0;
  final List<String> requestedPaths = [];

  MockDriveService({this.mockIndex});

  void setFile(String pathOrFileId, String content) {
    mockFiles[pathOrFileId] = content;
  }

  void setBinaryFile(String pathOrFileId, List<int> bytes) {
    mockBinaryFiles[pathOrFileId] = bytes;
  }

  void resetMetrics() {
    totalGetRequests = 0;
    gamePayloadRequests = 0;
    requestedPaths.clear();
  }

  @override
  Future<StorageValidationResult> verifyConnection() async {
    return StorageValidationResult.success(
      message: 'Mock storage is ready (${mockIndex?.totalGames ?? 0} games)',
      totalGames: mockIndex?.totalGames ?? 0,
      details: {'totalGames': mockIndex?.totalGames ?? 0},
    );
  }

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> refreshAuth() async => true;

  @override
  String resolveMediaUri(String mediaIdOrPath) {
    if (mediaIdOrPath.isEmpty) return '';
    if (mediaIdOrPath.startsWith('http://') ||
        mediaIdOrPath.startsWith('https://') ||
        mediaIdOrPath.startsWith('file://') ||
        mediaIdOrPath.startsWith('mock://')) {
      return mediaIdOrPath;
    }
    return 'mock://$mediaIdOrPath';
  }

  @override
  Map<String, String> getMediaHeaders({String? mediaUri}) => const {};

  @override
  Future<SyncIndex> fetchSyncIndex() async {
    totalGetRequests++;
    if (mockIndex != null) return mockIndex!;
    if (mockFiles.containsKey('sync_index.json')) {
      final json = jsonDecode(mockFiles['sync_index.json']!);
      return SyncIndex.fromJson(json);
    }
    throw StateError('MockDriveService: sync_index.json not set');
  }

  @override
  Future<List<int>> downloadFileBytes(String fileIdOrPath) async {
    totalGetRequests++;
    requestedPaths.add(fileIdOrPath);

    if (fileIdOrPath != 'manifest.json' && !fileIdOrPath.startsWith('manifest')) {
      gamePayloadRequests++;
    }

    if (mockBinaryFiles.containsKey(fileIdOrPath)) {
      return mockBinaryFiles[fileIdOrPath]!;
    }

    if (mockFiles.containsKey(fileIdOrPath)) {
      return utf8.encode(mockFiles[fileIdOrPath]!);
    }

    for (final entry in mockBinaryFiles.entries) {
      if (entry.key == fileIdOrPath) return entry.value;
    }
    for (final entry in mockFiles.entries) {
      if (entry.key == fileIdOrPath) return utf8.encode(entry.value);
    }

    throw StateError('MockDriveService: File not found for identifier "$fileIdOrPath"');
  }

  @override
  Future<String> downloadFileText(String fileIdOrPath) async {
    final bytes = await downloadFileBytes(fileIdOrPath);
    return utf8.decode(bytes);
  }

  @override
  Future<Map<String, dynamic>> fetchManifest({String? fileId}) async {
    totalGetRequests++;
    final key = fileId ?? 'manifest.json';
    if (mockFiles.containsKey(key)) {
      return jsonDecode(mockFiles[key]!) as Map<String, dynamic>;
    }
    return {};
  }
}
