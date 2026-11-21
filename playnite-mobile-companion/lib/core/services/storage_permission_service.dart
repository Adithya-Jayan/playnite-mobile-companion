import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Clean Dart service for checking and requesting Android storage permissions
/// and "All Files Access" (MANAGE_EXTERNAL_STORAGE) for local folder sync,
/// with safe no-op fallbacks for non-Android platforms (desktop, iOS, web, unit tests).
class StoragePermissionService {
  static const MethodChannel _channel = MethodChannel('com.playnite.companion/background_sync');

  @visibleForTesting
  static bool? mockPermissionGranted;

  static bool get isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether external storage / All Files Access permission is granted.
  /// On non-Android platforms, always returns true.
  static Future<bool> isStoragePermissionGranted() async {
    if (mockPermissionGranted != null) {
      return mockPermissionGranted!;
    }
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isStoragePermissionGranted');
      return result ?? false;
    } catch (e) {
      debugPrint('StoragePermissionService.isStoragePermissionGranted failed: $e');
      return false;
    }
  }

  /// Prompts the system settings dialog to grant All Files Access / storage permission.
  /// On non-Android platforms, returns true.
  static Future<bool> requestStoragePermission() async {
    if (mockPermissionGranted != null) {
      return mockPermissionGranted!;
    }
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestStoragePermission');
      return result ?? false;
    } catch (e) {
      debugPrint('StoragePermissionService.requestStoragePermission failed: $e');
      return false;
    }
  }

  /// Opens the system storage settings page for Playnite Mobile Companion.
  /// On non-Android platforms, returns true.
  static Future<bool> openStorageSettings() async {
    if (!isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('openStorageSettings');
      return result ?? false;
    } catch (e) {
      debugPrint('StoragePermissionService.openStorageSettings failed: $e');
      return false;
    }
  }
}
