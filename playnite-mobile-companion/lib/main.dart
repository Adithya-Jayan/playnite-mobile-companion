import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playnite_mobile_companion/core/config/app_constants.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/features/library/presentation/library_screen.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
      try {
        final configRepo = SyncConfigRepository(database);
        await configRepo.loadConfig();
      } catch (cfgErr) {
        debugPrint('Warning: Loading sync config encountered error: $cfgErr');
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

Future<void> _seedInitialLibrary(GameDao gameDao, SyncMetaDao syncMetaDao) async {
  final sampleGames = [
    UnifiedGamePayload(
      id: '008977a8-b225-4709-b96d-41ac44bef1c3',
      gameId: '1091500',
      pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
      name: 'Cyberpunk 2077',
      sortingName: 'Cyberpunk 2077',
      description:
          '<p>Cyberpunk 2077 is an open-world, action-adventure RPG set in the megalopolis of Night City, where you play as a cyberpunk mercenary wrapped up in a do-or-die fight for survival.</p>',
      playtimeSeconds: 756000, // 210 hours
      playCount: 48,
      isInstalled: true,
      favorite: true,
      userScore: 92,
      criticScore: 86,
      releaseDate: '2020-12-10',
      lastActivityUtc: DateTime.now().subtract(const Duration(hours: 4)).toUtc().toIso8601String(),
      source: const NamedItem(id: 'steam', name: 'Steam'),
      completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
      platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
      genres: const [NamedItem(id: 'rpg', name: 'Role-playing (RPG)'), NamedItem(id: 'action', name: 'Action')],
      developers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
      publishers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
      links: const [
        LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/1091500/'),
        LinkItem(name: 'PCGamingWiki', url: 'https://www.pcgamingwiki.com/wiki/Cyberpunk_2077'),
      ],
      media: const MediaPayload(
        coverDriveFileId: 'mock_cover_cyberpunk',
        coverSha256: '9a7d32c4b810e2f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9',
        backgroundDriveFileId: 'mock_bg_cyberpunk',
        logoDriveFileId: 'mock_logo_cyberpunk',
      ),
      addons: {
        'how_long_to_beat': {
          'main_story_seconds': 93600, // 26h
          'main_extra_seconds': 216000, // 60h
          'completionist_seconds': 374400, // 104h
        },
        'success_story': {
          'total': 44,
          'unlocked': 42,
          'locked': 2,
          'gamerscore': 840.0,
          'total_gamerscore': 1000.0,
          'achievements': [
            {
              'name': 'The World',
              'description': 'Complete the main storyline.',
              'date_unlocked_utc': '2025-06-12T18:30:00Z',
              'percent': 34.2,
              'gamer_score': 50.0,
            },
            {
              'name': 'Breathtaking',
              'description': 'Collect all items that once belonged to Johnny Silverhand.',
              'date_unlocked_utc': '2025-07-01T20:15:00Z',
              'percent': 12.8,
              'gamer_score': 30.0,
            },
            {
              'name': 'City Lights',
              'description': 'Complete all gigs and NCPD scanner hustles in City Center.',
              'date_unlocked_utc': null,
              'percent': 8.4,
              'gamer_score': 30.0,
            },
          ],
        },
        'game_activity': {
          'sessions': [
            {
              'date_session_utc': DateTime.now().subtract(const Duration(hours: 4)).toUtc().toIso8601String(),
              'elapsed_seconds': 7200,
              'action_name': 'Play',
            },
            {
              'date_session_utc': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
              'elapsed_seconds': 10800,
              'action_name': 'Play',
            },
          ],
        },
        'check_dlc': {
          'dlcs': [
            {
              'dlc_id': '2138330',
              'name': 'Phantom Liberty',
              'is_owned': true,
              'price': 29.99,
              'currency': '\$',
            },
          ],
        },
        'steam_reviews_viewer': {
          'positive_percent': 91,
          'total_reviews': 710240,
          'review_score_desc': 'Very Positive',
        },
        'system_checker': {
          'minimum': {
            'os': 'Windows 10 64-bit',
            'processor': 'Core i7-6700 or Ryzen 5 1600',
            'memory': '12 GB RAM',
            'graphics': 'GeForce GTX 1060 6GB or Radeon RX 580 8GB',
            'storage': '70 GB SSD',
          },
          'recommended': {
            'os': 'Windows 10 64-bit',
            'processor': 'Core i7-12700 or Ryzen 7 7800X3D',
            'memory': '16 GB RAM',
            'graphics': 'GeForce RTX 2060 SUPER or Radeon RX 5700 XT',
            'storage': '70 GB SSD',
          },
        },
      },
    ),
    UnifiedGamePayload(
      id: '008dd993-7507-4795-b1bb-862f9ce592be',
      gameId: '292030',
      pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
      name: 'The Witcher 3: Wild Hunt',
      sortingName: 'Witcher 3: Wild Hunt, The',
      description: 'You are Geralt of Rivia, mercenary monster slayer. Your track leads across a war-torn, monster-infested continent.',
      playtimeSeconds: 666000, // 185 hours
      playCount: 35,
      isInstalled: true,
      favorite: true,
      userScore: 96,
      criticScore: 93,
      releaseDate: '2015-05-18',
      lastActivityUtc: DateTime.now().subtract(const Duration(days: 5)).toUtc().toIso8601String(),
      source: const NamedItem(id: 'steam', name: 'Steam'),
      completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
      platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
      genres: const [NamedItem(id: 'rpg', name: 'Role-playing (RPG)')],
      developers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
      publishers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
      links: const [
        LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/292030/'),
      ],
      addons: {
        'how_long_to_beat': {
          'main_story_seconds': 185400, // 51.5h
          'main_extra_seconds': 370800, // 103h
          'completionist_seconds': 622800, // 173h
        },
        'check_dlc': {
          'dlcs': [
            {'dlc_id': 'hearts_of_stone', 'name': 'Hearts of Stone', 'is_owned': true, 'price': 9.99},
            {'dlc_id': 'blood_and_wine', 'name': 'Blood and Wine', 'is_owned': true, 'price': 19.99},
          ],
        },
      },
    ),
    UnifiedGamePayload(
      id: '01a54b98-653e-4361-bd8d-294b00cb3e21',
      gameId: '1245620',
      pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
      name: 'Elden Ring',
      sortingName: 'Elden Ring',
      description: 'THE NEW FANTASY ACTION RPG. Rise, Tarnished, and be guided by grace to brandish the power of the Elden Ring.',
      playtimeSeconds: 511200, // 142 hours
      playCount: 29,
      isInstalled: false,
      favorite: true,
      userScore: 95,
      criticScore: 96,
      releaseDate: '2022-02-25',
      lastActivityUtc: DateTime.now().subtract(const Duration(days: 14)).toUtc().toIso8601String(),
      source: const NamedItem(id: 'steam', name: 'Steam'),
      completionStatus: const NamedItem(id: 'beaten', name: 'Beaten'),
      platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
      genres: const [NamedItem(id: 'action', name: 'Action'), NamedItem(id: 'rpg', name: 'Role-playing (RPG)')],
      developers: const [NamedItem(id: 'fromsoft', name: 'FromSoftware Inc.')],
      publishers: const [NamedItem(id: 'bandai', name: 'Bandai Namco Entertainment')],
      addons: {
        'how_long_to_beat': {
          'main_story_seconds': 212400, // 59h
          'main_extra_seconds': 363600, // 101h
          'completionist_seconds': 486000, // 135h
        },
        'check_dlc': {
          'dlcs': [
            {'dlc_id': 'shadow_erdtree', 'name': 'Shadow of the Erdtree', 'is_owned': true, 'price': 39.99},
          ],
        },
      },
    ),
    UnifiedGamePayload(
      id: '028b0561-1250-4bc3-9fc7-789a6a84cf90',
      gameId: 'encased_epic',
      pluginId: '00000002-0000-0000-0000-000000000002',
      name: 'Encased: A Sci-Fi Post-Apocalyptic RPG',
      sortingName: 'Encased: A Sci-Fi Post-Apocalyptic RPG',
      description: 'A tactical sci-fi RPG set in an alternative 1970s where an enormous and inexplicable artifact was discovered in a remote desert.',
      playtimeSeconds: 93600, // 26 hours
      playCount: 12,
      isInstalled: true,
      favorite: false,
      userScore: 82,
      criticScore: 76,
      releaseDate: '2021-09-07',
      source: const NamedItem(id: 'epic', name: 'Epic Games'),
      completionStatus: const NamedItem(id: 'playing', name: 'Playing'),
      platforms: const [NamedItem(id: 'pc', name: 'PC (Windows)')],
      genres: const [NamedItem(id: 'rpg', name: 'Role-playing (RPG)')],
      developers: const [NamedItem(id: 'dark_crystal', name: 'Dark Crystal Games')],
      addons: {
        'custom_future_addon': {
          'sync_channel': 'alpha',
          'community_rating': 'Silver',
          'mods_active': ['HighResTextures', 'RebalancePatch'],
        },
      },
    ),
  ];

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
