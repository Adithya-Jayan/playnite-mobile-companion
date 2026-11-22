import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../features/sync/domain/sync_models.dart';
import '../services/storage_permission_service.dart';
import 'drive_api_service.dart';

/// Backwards compatibility typedef for LocalFolderValidationResult
typedef LocalFolderValidationResult = StorageValidationResult;

/// Service that reads Playnite export artifacts directly from a local device directory.
/// Ideal for testing, offline transfers (ADB / Syncthing), and users without GCP credentials.
class LocalFolderDriveService implements DriveApiService {
  final String basePath;

  LocalFolderDriveService(this.basePath);

  static bool _isPermissionDeniedException(Object e) {
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      if (code == 13 || e.message.toLowerCase().contains('permission denied')) {
        return true;
      }
    }
    final str = e.toString().toLowerCase();
    return str.contains('permission denied') || str.contains('errno = 13') || str.contains('errno: 13');
  }

  static String _permissionDeniedMessage(String path) {
    return 'Storage permission denied when accessing "$path". '
        'On Android, please grant "All Files Access" / Storage permission in Settings -> Apps -> Playnite Mobile Companion -> Permissions.';
  }

  /// Deep interface method verifying directory existence, storage permissions, and valid sync_index.json.
  @override
  Future<StorageValidationResult> verifyConnection() async {
    final trimmed = basePath.trim();
    if (trimmed.isEmpty) {
      return const StorageValidationResult(
        isValid: false,
        message: 'Please enter a directory path.',
      );
    }

    if (StoragePermissionService.isAndroid) {
      final hasPerm = await StoragePermissionService.isStoragePermissionGranted();
      if (!hasPerm) {
        return StorageValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(trimmed),
        );
      }
    }

    final dir = Directory(trimmed);
    try {
      if (!await dir.exists()) {
        return StorageValidationResult(
          isValid: false,
          message: 'Directory does not exist: "$trimmed"',
        );
      }
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        return StorageValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(trimmed),
        );
      }
      return StorageValidationResult(
        isValid: false,
        message: 'Cannot access directory: ${e.message}',
      );
    }

    final file = File('$trimmed/sync_index.json');
    try {
      if (!await file.exists()) {
        return StorageValidationResult(
          isValid: false,
          message: 'sync_index.json not found in "$trimmed". Make sure your Playnite export folder is copied here.',
        );
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final index = SyncIndex.fromJson(json);
      return StorageValidationResult(
        isValid: true,
        message: 'Valid export found (${index.totalGames} games, generated ${index.generatedAtUtc})',
        totalGames: index.totalGames,
        details: {
          'libraryId': index.libraryId,
          'totalGames': index.totalGames,
          'totalEntries': index.totalEntries,
        },
      );
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        return StorageValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(file.path),
        );
      }
      return StorageValidationResult(
        isValid: false,
        message: 'Error reading sync_index.json: ${e.message}',
      );
    } catch (e) {
      return StorageValidationResult(
        isValid: false,
        message: 'Invalid sync_index.json format: $e',
      );
    }
  }

  /// Preserved for backwards compatibility with legacy callers; delegates to [verifyConnection].
  Future<StorageValidationResult> validateFolder() => verifyConnection();

  @override
  Future<bool> requestPermissions() async {
    if (StoragePermissionService.isAndroid) {
      return await StoragePermissionService.requestStoragePermission();
    }
    return true;
  }

  @override
  Future<bool> refreshAuth() async => true;

  @override
  String resolveMediaUri(String mediaIdOrPath) {
    if (mediaIdOrPath.isEmpty) return '';
    if (mediaIdOrPath.startsWith('http://') ||
        mediaIdOrPath.startsWith('https://') ||
        mediaIdOrPath.startsWith('file://')) {
      return mediaIdOrPath;
    }
    final normalized = mediaIdOrPath.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains(':/')) {
      return 'file://$normalized';
    }
    final cleanBase = basePath.replaceAll('\\', '/');
    return 'file://$cleanBase/$normalized';
  }

  @override
  Map<String, String> getMediaHeaders({String? mediaUri}) => const {};

  @override
  Future<SyncIndex> fetchSyncIndex() async {
    if (StoragePermissionService.isAndroid) {
      final hasPerm = await StoragePermissionService.isStoragePermissionGranted();
      if (!hasPerm) {
        throw StateError(_permissionDeniedMessage('$basePath/sync_index.json'));
      }
    }

    final file = File('$basePath/sync_index.json');
    try {
      if (!await file.exists()) {
        throw StateError('sync_index.json not found in "$basePath". Make sure your Playnite export folder is copied here.');
      }
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SyncIndex.fromJson(json);
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        throw StateError(_permissionDeniedMessage(file.path));
      }
      rethrow;
    }
  }

  @override
  Future<List<int>> downloadFileBytes(String fileIdOrPath) async {
    // Clean Windows/POSIX backslashes
    final normalized = fileIdOrPath.replaceAll('\\', '/');
    try {
      var file = File('$basePath/$normalized');
      if (await file.exists()) {
        return await file.readAsBytes();
      }

      // Try relative or direct file
      file = File(normalized);
      if (await file.exists()) {
        return await file.readAsBytes();
      }

      throw StateError('Local sync file not found: "$fileIdOrPath" (checked in "$basePath")');
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        throw StateError(_permissionDeniedMessage(fileIdOrPath));
      }
      rethrow;
    }
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
    try {
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        debugPrint(_permissionDeniedMessage(file.path));
      } else {
        debugPrint('Error reading local manifest: $e');
      }
    } catch (e) {
      debugPrint('Error reading local manifest: $e');
    }
    return {};
  }
}
