import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

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

  // Alias mapping: maps secondary keys (e.g. relativePath, sha256) to primaryKey (e.g. driveFileId)
  // preventing physical duplication of files on disk.
  final Map<String, String> _aliasToPrimaryKey = {};
  @visibleForTesting
  Map<String, String> get aliasToPrimaryKey => Map.unmodifiable(_aliasToPrimaryKey);
  File? _aliasIndexFile;
  Timer? _aliasSaveTimer;

  // Set of keys marked as high priority (e.g. game detail view hero assets)
  final Set<String> _priorityKeys = {};

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
      _cacheDir = Directory.systemTemp.createTempSync('playnite_test_cache_');
      _aliasIndexFile = File(p.join(_cacheDir!.path, '_alias_index.json'));
      _isInitialized = true;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      return;
    }

    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(baseDir.path, 'media_cache', 'thumbnails'));
      _aliasIndexFile = File(p.join(_cacheDir!.path, '_alias_index.json'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      } else {
        // Fast index of existing files for O(1) synchronous hits
        final entries = _cacheDir!.listSync();
        for (final entry in entries) {
          if (entry is File) {
            final fileName = p.basename(entry.path);
            if (!fileName.startsWith('_')) {
              final key = p.basenameWithoutExtension(entry.path);
              _knownOnDisk.add(key);
            }
          }
        }

        // Load alias index if present
        if (_aliasIndexFile!.existsSync()) {
          try {
            final content = _aliasIndexFile!.readAsStringSync();
            final decoded = jsonDecode(content);
            if (decoded is Map) {
              for (final e in decoded.entries) {
                final alias = e.key.toString();
                final primary = e.value.toString();
                _aliasToPrimaryKey[alias] = primary;
                if (_knownOnDisk.contains(primary)) {
                  _knownOnDisk.add(alias);
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading alias index: $e');
          }
        } else {
          // Perform one-time deduplication pass for existing installations
          await deduplicateCache();
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
    final resolvedKey = _aliasToPrimaryKey[key] ?? key;

    if ((_knownOnDisk.contains(key) || _knownOnDisk.contains(resolvedKey)) && _cacheDir != null) {
      final file = File(p.join(_cacheDir!.path, '$resolvedKey.bin'));
      if (file.existsSync()) {
        _knownOnDisk.add(key);
        _knownOnDisk.add(resolvedKey);
        return file;
      } else {
        _knownOnDisk.remove(key);
        _knownOnDisk.remove(resolvedKey);
      }
    }
    return null;
  }

  /// Request an image download.
  /// If already on disk, completes immediately.
  /// Otherwise enqueues with LIFO priority (or immediate high priority for detail view).
  void load({
    required String mediaId,
    required void Function(File?) onComplete,
    bool isPriority = false,
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

    if (isPriority) {
      _priorityKeys.add(key);
    }

    // If already downloading or in-flight, listener is registered and will be notified on completion
    if (_inFlightKeys.contains(key) || _activeHttpRequests.containsKey(key)) {
      return;
    }

    // LIFO Priority: Move to the TOP of the queue (end of list for removeLast)
    _lifoQueue.remove(key);
    _lifoQueue.add(key);

    _pumpQueue();
  }

  /// Immediately prioritizes a list of assets for Game Detail view (background, cover, logo, related)
  /// and preempts offscreen background requests to dedicate full connection throughput.
  void prioritizeDetailView(List<String?> mediaIds) {
    for (final raw in mediaIds) {
      if (raw == null || raw.trim().isEmpty) continue;
      final key = sanitizeKey(raw.trim());
      _priorityKeys.add(key);
      if (_lifoQueue.contains(key)) {
        _lifoQueue.remove(key);
        _lifoQueue.add(key);
      }
    }
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
        _priorityKeys.remove(key);

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

    // Preemption: If priority keys are waiting to download and all connection slots are saturated,
    // abort the oldest non-priority active HTTP request to immediately liberate bandwidth!
    final hasWaitingPriority = _lifoQueue.any((k) => _priorityKeys.contains(k));
    if (hasWaitingPriority && _activeCount >= maxConcurrentDownloads) {
      for (final inFlightKey in _activeHttpRequests.keys.toList()) {
        if (!_priorityKeys.contains(inFlightKey)) {
          final activeReq = _activeHttpRequests.remove(inFlightKey);
          if (activeReq != null) {
            try {
              activeReq.abort();
            } catch (_) {}
            // Push aborted non-priority key back to bottom of queue to retry later
            _lifoQueue.insert(0, inFlightKey);
            _inFlightKeys.remove(inFlightKey);
            _activeCount = (_activeCount - 1).clamp(0, maxConcurrentDownloads);
            break; // Frees up a slot immediately
          }
        }
      }
    }

    while (_activeCount < maxConcurrentDownloads && _lifoQueue.isNotEmpty) {
      // If any priority key is in queue, pop it first; otherwise pop LIFO from end
      final priorityIdx = _lifoQueue.lastIndexWhere((k) => _priorityKeys.contains(k));
      final String key;
      if (priorityIdx >= 0) {
        key = _lifoQueue.removeAt(priorityIdx);
      } else {
        key = _lifoQueue.removeLast();
      }

      // Check if listeners are still interested
      final listeners = _listeners[key];
      if (listeners == null || listeners.isEmpty) {
        _keyToMediaId.remove(key);
        _priorityKeys.remove(key);
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
      final effectiveId = _aliasToPrimaryKey[key] ??
          _aliasToPrimaryKey[sanitizeKey(rawMediaId)] ??
          rawMediaId;
      final streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(effectiveId);
      if (streamUrl.isEmpty) {
        final callbacks = _listeners.remove(key);
        _keyToMediaId.remove(key);
        if (callbacks != null) {
          for (final cb in callbacks) {
            cb(null);
          }
        }
        return;
      }
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
      _priorityKeys.remove(key);
      _inFlightKeys.remove(key);
      _activeHttpRequests.remove(key);
      _activeCount = (_activeCount - 1).clamp(0, maxConcurrentDownloads);
      _pumpQueue();
    }
  }

  /// Persists a binary media payload directly into the flash disk cache.
  /// Used by DeltaPullManager to store pre-downloaded offline covers, backgrounds, and videos.
  /// Stores exactly ONE physical file on disk to prevent multi-gigabyte duplication across aliases.
  Future<void> saveToCache({
    required String keyOrMediaId,
    required List<int> bytes,
    List<String> aliases = const [],
  }) async {
    if (!_isInitialized) {
      await init();
    }
    if (_cacheDir == null) return;

    try {
      final primaryKey = sanitizeKey(keyOrMediaId);
      final primaryFile = File(p.join(_cacheDir!.path, '$primaryKey.bin'));
      await primaryFile.writeAsBytes(bytes, flush: true);
      _knownOnDisk.add(primaryKey);

      bool hasNewAliases = false;
      for (final alias in aliases) {
        if (alias.trim().isEmpty) continue;
        final aliasKey = sanitizeKey(alias);
        if (aliasKey != primaryKey) {
          _aliasToPrimaryKey[aliasKey] = primaryKey;
          _knownOnDisk.add(aliasKey);
          hasNewAliases = true;

          // If an older build wrote a duplicate file on disk, remove it to reclaim storage!
          final legacyDupFile = File(p.join(_cacheDir!.path, '$aliasKey.bin'));
          if (legacyDupFile.existsSync()) {
            try {
              legacyDupFile.deleteSync();
            } catch (_) {}
          }
        }
      }

      if (hasNewAliases) {
        _scheduleSaveAliasIndex();
      }

      // Notify any active listeners waiting on this image
      final listeners = _listeners.remove(primaryKey);
      _keyToMediaId.remove(primaryKey);
      _priorityKeys.remove(primaryKey);
      if (listeners != null) {
        for (final cb in listeners) {
          cb(primaryFile);
        }
      }
      for (final alias in aliases) {
        final aliasKey = sanitizeKey(alias);
        final aliasListeners = _listeners.remove(aliasKey);
        _keyToMediaId.remove(aliasKey);
        _priorityKeys.remove(aliasKey);
        if (aliasListeners != null) {
          for (final cb in aliasListeners) {
            cb(primaryFile);
          }
        }
      }
    } catch (e) {
      debugPrint('PlayniteImageLoader saveToCache error: $e');
    }
  }

  void _scheduleSaveAliasIndex() {
    _aliasSaveTimer?.cancel();
    _aliasSaveTimer = Timer(const Duration(milliseconds: 500), () {
      saveAliasIndex();
    });
  }

  /// Flushes in-memory alias mappings to `_alias_index.json` on disk.
  Future<void> saveAliasIndex() async {
    if (_cacheDir == null || _aliasIndexFile == null) return;
    try {
      await _aliasIndexFile!.writeAsString(jsonEncode(_aliasToPrimaryKey), flush: true);
    } catch (e) {
      debugPrint('PlayniteImageLoader saveAliasIndex error: $e');
    }
  }

  /// Registers all entries from a remote SyncIndex so relativePaths, legacy icon paths,
  /// and sha256s map directly to their Google Drive file ID without physical duplication.
  void registerRemoteIndex(SyncIndex remoteIndex) {
    for (final entry in remoteIndex.entries.values) {
      if (entry.driveFileId.isNotEmpty) {
        final driveId = entry.driveFileId;
        final relKey = sanitizeKey(entry.relativePath);
        _aliasToPrimaryKey[relKey] = driveId;

        if (entry.sha256.isNotEmpty) {
          _aliasToPrimaryKey[sanitizeKey(entry.sha256)] = driveId;
        }

        // Achievement icons alias mapping:
        // entry.relativePath: "media/{gameId}/achievements/{apiName}.jpg"
        // Also map legacy PC cache paths: "icon_cache\{gameId}\original\{apiName}.jpg"
        if (entry.relativePath.startsWith('media/') &&
            entry.relativePath.contains('/achievements/')) {
          final parts = entry.relativePath.split('/');
          if (parts.length >= 4) {
            final gameId = parts[1];
            final filename = parts[3];
            _aliasToPrimaryKey[sanitizeKey('icon_cache\\$gameId\\original\\$filename')] = driveId;
            _aliasToPrimaryKey[sanitizeKey('icon_cache/$gameId/original/$filename')] = driveId;
          }
        }
      }
    }
    _scheduleSaveAliasIndex();
  }

  /// Scans cache directory for physical duplicate files from older app builds,
  /// maps duplicates into the alias index, and deletes the redundant copies on disk.
  Future<int> deduplicateCache() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    int bytesReclaimed = 0;
    try {
      final files = _cacheDir!.listSync().whereType<File>().toList();
      final sizeMap = <int, List<File>>{};
      for (final f in files) {
        if (p.basename(f.path).startsWith('_')) continue;
        final len = f.lengthSync();
        if (len > 0) {
          sizeMap.putIfAbsent(len, () => []).add(f);
        }
      }

      for (final entry in sizeMap.entries) {
        if (entry.value.length < 2) continue;
        final group = entry.value;
        final primary = group.first;
        final primaryKey = p.basenameWithoutExtension(primary.path);

        for (int i = 1; i < group.length; i++) {
          final dupFile = group[i];
          final dupKey = p.basenameWithoutExtension(dupFile.path);
          _aliasToPrimaryKey[dupKey] = primaryKey;
          _knownOnDisk.add(dupKey);
          bytesReclaimed += dupFile.lengthSync();
          try {
            dupFile.deleteSync();
          } catch (_) {}
        }
      }

      if (_aliasIndexFile != null && bytesReclaimed > 0) {
        await saveAliasIndex();
      }
    } catch (e) {
      debugPrint('PlayniteImageLoader deduplicateCache error: $e');
    }
    return bytesReclaimed;
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
        if (f is File && !p.basename(f.path).startsWith('_')) {
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
      _aliasSaveTimer?.cancel();
      _knownOnDisk.clear();
      _aliasToPrimaryKey.clear();
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
