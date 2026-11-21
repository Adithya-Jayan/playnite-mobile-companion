import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../features/sync/domain/sync_models.dart';
import '../services/storage_permission_service.dart';
import 'drive_api_service.dart';

/// Structured validation result when checking local directory staging.
class LocalFolderValidationResult {
  final bool isValid;
  final bool permissionDenied;
  final String message;
  final int? totalGames;

  const LocalFolderValidationResult({
    required this.isValid,
    this.permissionDenied = false,
    required this.message,
    this.totalGames,
  });
}

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

  /// Verifies directory existence, storage permissions, and checks for valid sync_index.json.
  Future<LocalFolderValidationResult> validateFolder() async {
    final trimmed = basePath.trim();
    if (trimmed.isEmpty) {
      return const LocalFolderValidationResult(
        isValid: false,
        message: 'Please enter a directory path.',
      );
    }

    if (StoragePermissionService.isAndroid) {
      final hasPerm = await StoragePermissionService.isStoragePermissionGranted();
      if (!hasPerm) {
        return LocalFolderValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(trimmed),
        );
      }
    }

    final dir = Directory(trimmed);
    try {
      if (!await dir.exists()) {
        return LocalFolderValidationResult(
          isValid: false,
          message: 'Directory does not exist: "$trimmed"',
        );
      }
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        return LocalFolderValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(trimmed),
        );
      }
      return LocalFolderValidationResult(
        isValid: false,
        message: 'Cannot access directory: ${e.message}',
      );
    }

    final file = File('$trimmed/sync_index.json');
    try {
      if (!await file.exists()) {
        return LocalFolderValidationResult(
          isValid: false,
          message: 'sync_index.json not found in "$trimmed". Make sure your Playnite export folder is copied here.',
        );
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final index = SyncIndex.fromJson(json);
      return LocalFolderValidationResult(
        isValid: true,
        message: 'Valid export found (${index.totalGames} games, generated ${index.generatedAtUtc})',
        totalGames: index.totalGames,
      );
    } on FileSystemException catch (e) {
      if (_isPermissionDeniedException(e)) {
        return LocalFolderValidationResult(
          isValid: false,
          permissionDenied: true,
          message: _permissionDeniedMessage(file.path),
        );
      }
      return LocalFolderValidationResult(
        isValid: false,
        message: 'Error reading sync_index.json: ${e.message}',
      );
    } catch (e) {
      return LocalFolderValidationResult(
        isValid: false,
        message: 'Invalid sync_index.json format: $e',
      );
    }
  }

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
