import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Clean Dart service for managing background execution, partial wake locks,
/// and battery optimization settings on Android, with safe no-op fallbacks for
/// non-Android platforms (desktop, web, unit tests).
class BackgroundSyncService {
  static const MethodChannel _channel = MethodChannel('com.playnite.companion/background_sync');

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Acquires a partial wake lock keeping the CPU running and network connections alive
  /// even when the app is in the background or screen turns off.
  static Future<bool> acquireWakeLock({int timeoutMs = 15 * 60 * 1000}) async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('acquireWakeLock', {'timeoutMs': timeoutMs});
      return result ?? false;
    } catch (e) {
      debugPrint('BackgroundSyncService.acquireWakeLock failed: $e');
      return false;
    }
  }

  /// Releases the partial wake lock safely.
  static Future<bool> releaseWakeLock() async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('releaseWakeLock');
      return result ?? false;
    } catch (e) {
      debugPrint('BackgroundSyncService.releaseWakeLock failed: $e');
      return false;
    }
  }

  /// Checks whether battery optimizations are ignored (unrestricted background execution allowed).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      debugPrint('BackgroundSyncService.isIgnoringBatteryOptimizations failed: $e');
      return false;
    }
  }

  /// Prompts the system dialog requesting to ignore battery optimizations for Playnite Companion.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      debugPrint('BackgroundSyncService.requestIgnoreBatteryOptimizations failed: $e');
      return false;
    }
  }

  /// Opens the system Battery Optimization settings page as a fallback.
  static Future<bool> openBatteryOptimizationSettings() async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return result ?? false;
    } catch (e) {
      debugPrint('BackgroundSyncService.openBatteryOptimizationSettings failed: $e');
      return false;
    }
  }
}
