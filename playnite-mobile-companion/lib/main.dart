import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playnite_mobile_companion/core/config/app_constants.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/google_drive_api_service.dart';
import 'package:playnite_mobile_companion/core/services/playnite_image_loader.dart';
import 'package:playnite_mobile_companion/features/library/presentation/library_screen.dart';
import 'package:playnite_mobile_companion/features/sync/data/demo_library_data.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 0. Tune global image cache for 7,000-game library smooth scrolling
    PaintingBinding.instance.imageCache.maximumSize = 2500;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 256 * 1024 * 1024; // 256 MB memory limit

    // 1. Global Flutter framework error handling
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError caught: ${details.exception}\n${details.stack}');
    };

    // 2. Global platform dispatcher error handling (handles asynchronous unhandled errors)
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error caught: $error\n$stack');
      return true; // Prevents crash
    };

    // 3. Custom ErrorWidget for widget build crashes
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: const Color(0xFF13151B),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56, color: Colors.orangeAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Rendering Error Encountered',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${details.exception}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    };

    final database = AppDatabase.instance;
    String? startupError;

    try {
      await database.init();

      // Seed sample games if database is empty on first launch
      try {
        final gameDao = GameDao(database);
        final count = await gameDao.getGamesCount();
        if (count == 0) {
          await _seedInitialLibrary(gameDao, SyncMetaDao(database));
        }
      } catch (seedErr) {
        debugPrint('Warning: Seeding initial library encountered error: $seedErr');
      }

      // Initialize persistent sync configuration
      SyncConfigRepository? configRepo;
      try {
        configRepo = SyncConfigRepository(database);
        await configRepo.loadConfig();
      } catch (cfgErr) {
        debugPrint('Warning: Loading sync config encountered error: $cfgErr');
      }

      // Initialize persistent high-performance image cache
      try {
        await PlayniteImageLoader.instance.init();
        if (configRepo != null) {
          final repo = configRepo;
          PlayniteImageLoader.instance.setTokenRefresher(() async {
            try {
              final latest = await repo.loadConfig();
              if (latest.storageType == SyncStorageType.googleDrive &&
                  latest.googleRefreshToken.isNotEmpty &&
                  latest.googleClientId.isNotEmpty) {
                final driveService = repo.createDriveService(latest);
                if (driveService is GoogleDriveApiService) {
                  final refreshed = await driveService.refreshAccessToken();
                  if (refreshed) {
                    final updatedConfig = await repo.loadConfig();
                    return updatedConfig.googleAccessToken;
                  }
                }
              }
            } catch (err) {
              debugPrint('Automatic image loader token refresh encountered error: $err');
            }
            return null;
          });
        }
      } catch (loaderErr) {
        debugPrint('Warning: Image loader initialization encountered error: $loaderErr');
      }
    } catch (e, stack) {
      debugPrint('FATAL: Database initialization error: $e\n$stack');
      startupError = e.toString();
    }

    runApp(
      ProviderScope(
        child: PlayniteCompanionApp(
          database: database,
          startupError: startupError,
        ),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught Zone Error: $error\n$stack');
  });
}

class PlayniteCompanionApp extends StatelessWidget {
  final AppDatabase database;
  final String? startupError;

  const PlayniteCompanionApp({
    super.key,
    required this.database,
    this.startupError,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: startupError != null
          ? StartupErrorScreen(error: startupError!, database: database)
          : LibraryScreen(database: database),
    );
  }
}

class StartupErrorScreen extends StatefulWidget {
  final String error;
  final AppDatabase database;

  const StartupErrorScreen({
    super.key,
    required this.error,
    required this.database,
  });

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _isRetrying = false;

  Future<void> _retry() async {
    setState(() => _isRetrying = true);
    try {
      await widget.database.init();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LibraryScreen(database: widget.database),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRetrying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization retry failed: $e'), backgroundColor: AppTheme.accentRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Playnite Companion - Startup'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orangeAccent),
              const SizedBox(height: 16),
              const Text(
                'Initialization Issue',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'The local SQLite database could not be initialized automatically. Details below:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  widget.error,
                  style: const TextStyle(fontSize: 12, color: AppTheme.accentRed, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: _isRetrying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Retry Initialization',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: _isRetrying ? null : _retry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Future<void> seedInitialLibrary(GameDao gameDao, SyncMetaDao syncMetaDao) =>
    _seedInitialLibrary(gameDao, syncMetaDao);

Future<void> _seedInitialLibrary(GameDao gameDao, SyncMetaDao syncMetaDao) async {
  final sampleGames = DemoLibraryData.getDemoGames();

  await gameDao.batchUpsertGames(sampleGames);

  // Register mock sync metadata entries
  final indexEntries = sampleGames.map((g) {
    return IndexEntry(
      relativePath: 'games/${g.id}.json',
      sha256: 'initial_hash_${g.id}',
      sizeBytes: 14000,
      modifiedUtc: DateTime.now().toUtc().toIso8601String(),
      driveFileId: 'mock_drive_${g.id}',
      mimeType: 'application/json',
      category: 'game_metadata',
      gameId: g.id,
    );
  }).toList();

  await syncMetaDao.batchUpsertEntries(indexEntries);
}
