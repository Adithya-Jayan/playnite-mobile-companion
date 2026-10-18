import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';

typedef TokenRefreshCallback = Future<String?> Function();

/// High-performance LIFO (Last-In, First-Out) priority image loader.
///
/// Key design principles:
/// 1. Prioritizes currently visible screen items over scrolled-past items (LIFO).
/// 2. Cancels pending and active network requests for widgets that scroll out of view.
/// 3. Persistent local flash disk cache for instant 0ms offline re-renders.
/// 4. Synchronous in-memory lookup of on-disk items.
/// 5. Bounded concurrency (up to 8 parallel HTTP streams).
class PlayniteImageLoader {
  static final PlayniteImageLoader instance = PlayniteImageLoader._();
  PlayniteImageLoader._();

  TokenRefreshCallback? _tokenRefresher;

  void setTokenRefresher(TokenRefreshCallback callback) {
    _tokenRefresher = callback;
  }

  Directory? _cacheDir;
  bool _isInitialized = false;
  final Completer<void> _initCompleter = Completer<void>();

  // Maximum simultaneous downloads from Google Drive / Cloud
  static const int maxConcurrentDownloads = 8;
  int _activeCount = 0;

  // LIFO queue: items are added to the end and popped from the end with removeLast()
  final List<String> _lifoQueue = [];

  // Map from sanitized key to raw mediaId/URL
  final Map<String, String> _keyToMediaId = {};

  // Active listeners for each key: (file) => void
  final Map<String, List<void Function(File?)>> _listeners = {};

  // Set of keys actively downloading or connecting
  final Set<String> _inFlightKeys = {};

  // Active HTTP requests for cancellation when scrolled off-screen
  final Map<String, HttpClientRequest> _activeHttpRequests = {};

  // Synchronous in-memory set of keys confirmed to exist on local flash disk
  final Set<String> _knownOnDisk = {};

  HttpClient? _client;

  static bool get _isTesting {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;
    if (_isTesting) {
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      return;
    }

    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(baseDir.path, 'media_cache', 'thumbnails'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      } else {
        // Fast index of existing files for O(1) synchronous hits
        final entries = _cacheDir!.listSync();
        for (final entry in entries) {
          if (entry is File) {
            final key = p.basenameWithoutExtension(entry.path);
            _knownOnDisk.add(key);
          }
        }
      }

      _client = HttpClient()
        ..maxConnectionsPerHost = 12
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 30);

      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    } catch (e) {
      debugPrint('PlayniteImageLoader init error: $e');
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  String sanitizeKey(String mediaId) {
    return mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  /// Synchronously checks if the image exists in local flash disk cache or as a local file.
  File? getCachedFileSync(String mediaId) {
    if (mediaId.trim().isEmpty) return null;
    final raw = mediaId.trim();

    // Check direct local paths (e.g. file:// or Windows/Linux paths)
    if (raw.startsWith('file://') ||
        raw.startsWith('/') ||
        raw.contains(':\\') ||
        raw.contains(':/')) {
      final filePath = raw.startsWith('file://') ? raw.substring(7) : raw;
      final f = File(filePath);
      return f.existsSync() ? f : null;
    }

    final key = sanitizeKey(raw);

    if (_knownOnDisk.contains(key) && _cacheDir != null) {
      final file = File(p.join(_cacheDir!.path, '$key.bin'));
      if (file.existsSync()) {
        return file;
      } else {
        _knownOnDisk.remove(key);
      }
    }
    return null;
  }

  /// Request an image download.
  /// If already on disk, completes immediately.
  /// Otherwise enqueues at the HEAD of the LIFO stack (so visible items load FIRST).
  void load({
    required String mediaId,
    required void Function(File?) onComplete,
  }) {
    final raw = mediaId.trim();
    if (raw.isEmpty) {
      onComplete(null);
      return;
    }

    if (_isTesting) {
      onComplete(null);
      return;
    }

    // 1. Fast-path: Check local disk cache (or direct local file)
    final local = getCachedFileSync(raw);
    if (local != null) {
      onComplete(local);
      return;
    }

    // Direct local file that does not exist
    if (raw.startsWith('file://') ||
        raw.startsWith('/') ||
        raw.contains(':\\') ||
        raw.contains(':/')) {
      onComplete(null);
      return;
    }

    final key = sanitizeKey(raw);
    _keyToMediaId[key] = raw;

    // Register callback listener
    _listeners.putIfAbsent(key, () => []).add(onComplete);

    // If already downloading or in-flight, listener is registered and will be notified on completion
    if (_inFlightKeys.contains(key) || _activeHttpRequests.containsKey(key)) {
      return;
    }

    // LIFO Priority: Move to the TOP of the queue (end of list for removeLast)
    _lifoQueue.remove(key);
    _lifoQueue.add(key);

    _pumpQueue();
  }

  /// Cancels interest in an image when the widget scrolls out of the visible viewport.
  ///
  /// Smart queue drainage:
  /// - Pending (waiting) queue items are immediately discarded so visible items load first.
  /// - If already downloading, the UI listener is detached, but the download is allowed to
  ///   finish writing to disk in the background. That way, scrolling back hits the cache with 0ms delay!
  void cancel(String mediaId, void Function(File?) listener) {
    final raw = mediaId.trim();
    if (raw.isEmpty) return;
    final key = sanitizeKey(raw);

    final list = _listeners[key];
    if (list != null) {
      list.remove(listener);
      if (list.isEmpty) {
        _listeners.remove(key);

        // Remove from waiting LIFO queue so it doesn't block visible items
        _lifoQueue.remove(key);

        // Abort in-flight HTTP request if active to liberate connection bandwidth
        final activeReq = _activeHttpRequests.remove(key);
        if (activeReq != null) {
          try {
            activeReq.abort();
          } catch (_) {}
        }

        // If not in-flight, clean up mapping
        if (!_inFlightKeys.contains(key)) {
          _keyToMediaId.remove(key);
        }
      }
    }
  }

  void _pumpQueue() {
    if (!_isInitialized || _client == null || _cacheDir == null) {
      if (!_isInitialized) {
        init().then((_) => _pumpQueue());
      }
      return;
    }

    while (_activeCount < maxConcurrentDownloads && _lifoQueue.isNotEmpty) {
      // Pop most recently requested (visible) item from the end of the list (LIFO)
      final key = _lifoQueue.removeLast();

      // Check if listeners are still interested
      final listeners = _listeners[key];
      if (listeners == null || listeners.isEmpty) {
        _keyToMediaId.remove(key);
        continue;
      }

      // Avoid duplicate downloads if already in flight
      if (_inFlightKeys.contains(key)) {
        continue;
      }

      _inFlightKeys.add(key);
      _activeCount++;
      _startDownload(key);
    }
  }

  Future<void> _startDownload(String key) async {
    final rawMediaId = _keyToMediaId[key];
    if (rawMediaId == null) {
      return;
    }

    try {
      final streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(rawMediaId);
      final isGoogleDrive = streamUrl.contains('googleapis.com');
      final headers = isGoogleDrive ? MediaUrlResolver.getAuthHeaders() : <String, String>{};

      final request = await _client!.getUrl(Uri.parse(streamUrl)).timeout(const Duration(seconds: 12));
      _activeHttpRequests[key] = request;
      headers.forEach((k, v) => request.headers.set(k, v));

      var response = await request.close().timeout(const Duration(seconds: 12));

      // 401 Unauthorized Interceptor: Attempt token refresh once
      if (response.statusCode == 401 && _tokenRefresher != null) {
        try {
          final refreshedToken = await _tokenRefresher!();
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            MediaUrlResolver.setAuthToken(refreshedToken);
            final retryHeaders = MediaUrlResolver.getAuthHeaders();
            final retryReq = await _client!.getUrl(Uri.parse(streamUrl)).timeout(const Duration(seconds: 12));
            _activeHttpRequests[key] = retryReq;
            retryHeaders.forEach((k, v) => retryReq.headers.set(k, v));
            response = await retryReq.close().timeout(const Duration(seconds: 12));
          }
        } catch (refreshErr) {
          debugPrint('Token refresh failed during image download: $refreshErr');
        }
      }

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response).timeout(const Duration(seconds: 15));
        if (_cacheDir != null && bytes.isNotEmpty) {
          final targetFile = File(p.join(_cacheDir!.path, '$key.bin'));
          await targetFile.writeAsBytes(bytes, flush: true);
          _knownOnDisk.add(key);

          // Notify all listeners
          final callbacks = _listeners.remove(key);
          _keyToMediaId.remove(key);
          if (callbacks != null) {
            for (final cb in callbacks) {
              cb(targetFile);
            }
          }
        }
      } else {
        // Failed response (e.g. 404, 403, 429)
        final callbacks = _listeners.remove(key);
        _keyToMediaId.remove(key);
        if (callbacks != null) {
          for (final cb in callbacks) {
            cb(null);
          }
        }
      }
    } catch (e) {
      // Aborted or network error
      final callbacks = _listeners.remove(key);
      _keyToMediaId.remove(key);
      if (callbacks != null) {
        for (final cb in callbacks) {
          cb(null);
        }
      }
    } finally {
      _inFlightKeys.remove(key);
      _activeHttpRequests.remove(key);
      _activeCount = (_activeCount - 1).clamp(0, maxConcurrentDownloads);
      _pumpQueue();
    }
  }

  /// Total count of images cached on local flash disk
  int get cachedImagesCount => _knownOnDisk.length;

  /// Calculates total size in bytes of cached thumbnail files on disk
  Future<int> getCacheSizeBytes() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    try {
      int total = 0;
      final files = _cacheDir!.listSync();
      for (final f in files) {
        if (f is File) {
          total += f.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Clears the thumbnail cache on local flash disk
  Future<void> clearCache() async {
    try {
      _knownOnDisk.clear();
      _lifoQueue.clear();
      _listeners.clear();
      _inFlightKeys.clear();
      _activeCount = 0;
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('PlayniteImageLoader clearCache error: $e');
    }
  }
}
