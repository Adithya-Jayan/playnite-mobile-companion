import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../features/sync/domain/sync_models.dart';
import 'drive_api_service.dart';

/// Service that reads Playnite export artifacts directly from a local device directory.
/// Ideal for testing, offline transfers (ADB / Syncthing), and users without GCP credentials.
class LocalFolderDriveService implements DriveApiService {
  final String basePath;

  LocalFolderDriveService(this.basePath);

  @override
  Future<SyncIndex> fetchSyncIndex() async {
    final file = File('$basePath/sync_index.json');
    if (!await file.exists()) {
      throw StateError('sync_index.json not found in "$basePath". Make sure your Playnite export folder is copied here.');
    }
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return SyncIndex.fromJson(json);
  }

  @override
  Future<List<int>> downloadFileBytes(String fileIdOrPath) async {
    // Clean Windows/POSIX backslashes
    final normalized = fileIdOrPath.replaceAll('\\', '/');
    var file = File('$basePath/$normalized');
    if (await file.exists()) {
      return file.readAsBytes();
    }

    // Try relative or direct file
    file = File(normalized);
    if (await file.exists()) {
      return file.readAsBytes();
    }

    throw StateError('Local sync file not found: "$fileIdOrPath" (checked in "$basePath")');
  }

  @override
  Future<String> downloadFileText(String fileIdOrPath) async {
    final bytes = await downloadFileBytes(fileIdOrPath);
    return utf8.decode(bytes);
  }

  @override
  Future<Map<String, dynamic>> fetchManifest({String? fileId}) async {
    final fileName = fileId ?? 'manifest.json';
    final file = File('$basePath/$fileName');
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error reading local manifest: $e');
      }
    }
    return {};
  }
}
