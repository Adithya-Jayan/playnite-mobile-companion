import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/database/daos/sync_meta_dao.dart';
import 'package:playnite_mobile_companion/core/network/drive_api_service.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/addon_section_registry.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/fallback_addon_section.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/library/domain/sort_options.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Configurable mock Drive API service for end-to-end integration and fault-injection testing.
class TestConfigurableDriveService implements DriveApiService {
  SyncIndex remoteIndex;
  final Map<String, String> remoteFiles;
  bool simulateNetworkFailure = false;
  String? corruptFilePath;
  int downloadCalls = 0;

  TestConfigurableDriveService({
    required this.remoteIndex,
    required this.remoteFiles,
  });

  @override
  Future<SyncIndex> fetchSyncIndex() async {
    if (simulateNetworkFailure) {
      throw const SocketException('Simulated network failure: connection refused');
    }
    return remoteIndex;
  }

  @override
  Future<String> downloadFileText(String fileIdOrPath) async {
    downloadCalls++;
    if (simulateNetworkFailure) {
      throw const SocketException('Simulated network interruption during file transfer');
    }

    if (corruptFilePath != null &&
        (fileIdOrPath == corruptFilePath ||
            remoteIndex.entries[corruptFilePath]?.driveFileId == fileIdOrPath)) {
      return '{ "syntax_error": [ unclosed array corrupt file content';
    }

    // 1. Direct match
    if (remoteFiles.containsKey(fileIdOrPath)) {
      return remoteFiles[fileIdOrPath]!;
    }

    // 2. Lookup by driveFileId
    for (final entry in remoteIndex.entries.values) {
      if (entry.driveFileId == fileIdOrPath && remoteFiles.containsKey(entry.relativePath)) {
        return remoteFiles[entry.relativePath]!;
      }
    }

    // 3. Lookup by relativePath
    for (final entry in remoteIndex.entries.values) {
      if (entry.relativePath == fileIdOrPath && remoteFiles.containsKey(entry.driveFileId)) {
        return remoteFiles[entry.driveFileId]!;
      }
    }

    throw StateError('File not found: $fileIdOrPath');
  }

  @override
  Future<List<int>> downloadFileBytes(String fileIdOrPath) async {
    final text = await downloadFileText(fileIdOrPath);
    return utf8.encode(text);
  }

  @override
  Future<Map<String, dynamic>> fetchManifest({String? fileId}) async {
    if (simulateNetworkFailure) {
      throw const SocketException('Simulated network failure: connection refused');
    }
    final raw = remoteFiles['manifest.json'] ?? '{}';
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('End-to-End Integration & Edge-Case Pipeline Tests', () {
    late AppDatabase database;
    late GameDao gameDao;
    late SyncMetaDao syncMetaDao;

    // Game 1: The Witcher 3 (Full metadata, rich addons, CAS media)
    const witcherId = '3d2a71f4-90aa-43e9-a035-77ce5eb018ee';
    final witcherPayload = {
      'schema_version': '1.0.0',
      'id': witcherId,
      'game_id': '292030',
      'plugin_id': 'cb91dfa9-9e08-4169-acbe-023a1714d49a',
      'name': 'The Witcher 3: Wild Hunt',
      'sorting_name': 'Witcher 3: Wild Hunt, The',
      'description': '<p>Become a monster slayer for hire.</p>',
      'notes': 'Award-winning dark fantasy masterpiece.',
      'playtime_seconds': 432000,
      'play_count': 45,
      'added_utc': '2020-01-15T10:00:00.000Z',
      'modified_utc': '2026-10-15T18:00:00.000Z',
      'last_activity_utc': '2026-10-14T22:30:00.000Z',
      'recent_activity_utc': '2026-10-14T22:30:00.000Z',
      'release_date': '2015-05-19',
      'is_installed': true,
      'install_directory': r'D:\Games\Steam\steamapps\common\The Witcher 3',
      'install_size_bytes': 53687091200,
      'hidden': false,
      'favorite': true,
      'version': '4.04',
      'user_score': 98,
      'critic_score': 93,
      'community_score': 95,
      'source': {
        'id': 'cb91dfa9-9e08-4169-acbe-023a1714d49a',
        'name': 'Steam',
      },
      'completion_status': {
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Played',
      },
      'platforms': [
        {'id': '22222222-2222-2222-2222-222222222222', 'name': 'PC (Windows)', 'spec_id': 'pc_windows'}
      ],
      'genres': [
        {'id': '33333333-3333-3333-3333-333333333333', 'name': 'Role-playing (RPG)'},
        {'id': '33333333-3333-3333-3333-333333333334', 'name': 'Open World'}
      ],
      'developers': [
        {'id': '44444444-4444-4444-4444-444444444444', 'name': 'CD PROJEKT RED'}
      ],
      'publishers': [
        {'id': '55555555-5555-5555-5555-555555555555', 'name': 'CD PROJEKT'}
      ],
      'categories': [
        {'id': '66666666-6666-6666-6666-666666666666', 'name': 'Single-player'}
      ],
      'tags': [
        {'id': '77777777-7777-7777-7777-777777777777', 'name': 'Fantasy'},
        {'id': '77777777-7777-7777-7777-777777777778', 'name': 'Story Rich'}
      ],
      'features': [
        {'id': '88888888-8888-8888-8888-888888888888', 'name': 'Cloud Saves'},
        {'id': '88888888-8888-8888-8888-888888888889', 'name': 'Achievements'}
      ],
      'links': [
        {'name': 'Store', 'url': 'https://store.steampowered.com/app/292030'},
        {'name': 'Wiki', 'url': 'https://witcher.fandom.com'}
      ],
      'media': {
        'cover': {
          'relative_path': 'media/covers/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.webp',
          'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          'format': 'webp',
          'width': 600,
          'height': 900,
          'drive_file_id': 'drive_file_witcher_cover_v1'
        },
        'background': {
          'relative_path': 'media/backgrounds/f6e5d4c3b2a10000000000000000000000000000000000000000000000000000.webp',
          'sha256': 'f6e5d4c3b2a10000000000000000000000000000000000000000000000000000',
          'format': 'webp',
          'width': 1920,
          'height': 1080,
          'drive_file_id': 'drive_file_witcher_bg'
        }
      },
      'addons': {
        'success_story': {
          'total': 78,
          'unlocked': 65,
          'achievements': [
            {
              'api_name': 'ACH_01',
              'name': 'Lilac and Gooseberries',
              'description': 'Find Yennefer of Vengerberg.',
              'url_unlocked': 'https://cdn.steam.com/ach_01.png',
              'url_locked': 'https://cdn.steam.com/ach_01_locked.png',
              'date_unlocked_utc': '2020-01-16T14:22:00Z',
              'percent': 92.5,
              'gamer_score': 15.0,
              'is_hidden': false
            }
          ]
        },
        'game_activity': {
          'sessions': [
            {
              'date_session_utc': '2026-10-14T20:00:00Z',
              'elapsed_seconds': 9000,
              'action_name': 'Play'
            }
          ]
        },
        'how_long_to_beat': {
          'hltb_id': '10232',
          'main_story_seconds': 185400,
          'main_extra_seconds': 367200,
          'completionist_seconds': 622800,
          'all_styles_seconds': 374400,
          'url': 'https://howlongtobeat.com/game/10232'
        },
        'check_dlc': {
          'dlcs': [
            {
              'dlc_id': '378648',
              'name': 'Hearts of Stone',
              'is_owned': true,
              'price': 9.99,
              'currency': 'USD',
              'url': 'https://store.steampowered.com/app/378648'
            },
            {
              'dlc_id': '378649',
              'name': 'Blood and Wine',
              'is_owned': true,
              'price': 19.99,
              'currency': 'USD',
              'url': 'https://store.steampowered.com/app/378649'
            }
          ]
        },
        'steam_reviews': {
          'review_score': 9,
          'review_score_description': 'Overwhelmingly Positive',
          'positive_count': 678000,
          'negative_count': 24000
        }
      }
    };

    // Game 2: Cyberpunk 2077
    const cyberpunkId = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';
    final cyberpunkPayload = {
      'schema_version': '1.0.0',
      'id': cyberpunkId,
      'game_id': '1091500',
      'plugin_id': 'cb91dfa9-9e08-4169-acbe-023a1714d49a',
      'name': 'Cyberpunk 2077',
      'sorting_name': 'Cyberpunk 2077',
      'description': 'Open-world action-adventure RPG in Night City.',
      'notes': 'Path tracing benchmark.',
      'playtime_seconds': 180000,
      'play_count': 20,
      'added_utc': '2020-12-10T12:00:00.000Z',
      'modified_utc': '2026-10-12T15:00:00.000Z',
      'last_activity_utc': '2026-10-12T19:00:00.000Z',
      'is_installed': true,
      'install_size_bytes': 75161927680,
      'hidden': false,
      'favorite': false,
      'user_score': 85,
      'critic_score': 86,
      'community_score': 82,
      'source': {'id': 'cb91dfa9-9e08-4169-acbe-023a1714d49a', 'name': 'Steam'},
      'completion_status': {'id': '22222222-2222-2222-2222-222222222222', 'name': 'Completed'},
      'platforms': [{'id': '22222222-2222-2222-2222-222222222222', 'name': 'PC (Windows)'}],
      'genres': [{'id': '33333333-3333-3333-3333-333333333333', 'name': 'Role-playing (RPG)'}],
      'developers': [{'id': '44444444-4444-4444-4444-444444444444', 'name': 'CD PROJEKT RED'}],
      'publishers': [{'id': '55555555-5555-5555-5555-555555555555', 'name': 'CD PROJEKT'}],
      'media': {
        'cover': {
          'relative_path': 'media/covers/cyberpunk_cover_v1.webp',
          'sha256': 'cp2077_initial_hash_111111111111111111111111111111111111111111111111',
          'format': 'webp',
          'drive_file_id': 'drive_file_cyberpunk_cover_v1'
        }
      },
      'addons': {}
    };

    // Game 3: Indie Unknown Addon Game (Tests Dynamic Addon Fallback)
    const indieId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final indiePayload = {
      'schema_version': '1.0.0',
      'id': indieId,
      'game_id': 'indie_999',
      'plugin_id': '00000000-0000-0000-0000-000000000000',
      'name': 'Indie Novelty',
      'sorting_name': 'Indie Novelty',
      'playtime_seconds': 600,
      'play_count': 1,
      'is_installed': false,
      'hidden': false,
      'favorite': false,
      'addons': {
        'future_haptics_addon': {
          'haptic_profile': 'ultra_rumble',
          'firmware_version': '2.1.0'
        }
      }
    };

    // Manifest JSON
    final manifestPayload = {
      'version': '1.0.0',
      'generated_at_utc': '2026-10-15T18:00:00.000Z',
      'library_summary': {
        'total_games': 3,
        'installed_games': 2,
        'favorite_games': 1,
        'hidden_games': 0,
        'total_playtime_seconds': 612600,
        'total_play_count': 66
      },
      'sources': [{'id': 'cb91dfa9-9e08-4169-acbe-023a1714d49a', 'name': 'Steam'}],
      'completion_statuses': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'Played'},
        {'id': '22222222-2222-2222-2222-222222222222', 'name': 'Completed'}
      ]
    };

    setUp(() async {
      database = AppDatabase.instance;
      await database.init(inMemory: true);
      await database.reset();
      gameDao = GameDao(database);
      syncMetaDao = SyncMetaDao(database);
      AddonSectionRegistry.reset();
    });

    tearDown(() async {
      await database.close();
    });

    test('1. End-to-End Pipeline: Ingests C# Export Artifacts with 100% Field Preservation into SQLite', () async {
      final remoteFiles = <String, String>{
        'manifest.json': jsonEncode(manifestPayload),
        'games/$witcherId.json': jsonEncode(witcherPayload),
        'games/$cyberpunkId.json': jsonEncode(cyberpunkPayload),
        'games/$indieId.json': jsonEncode(indiePayload),
      };

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:00:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 3,
        totalEntries: 4,
        totalSizeBytes: 12000,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'hash_manifest',
            sizeBytes: 1500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'drive_manifest',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'hash_witcher_v1',
            sizeBytes: 4500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'drive_witcher',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'hash_cp_v1',
            sizeBytes: 3000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'drive_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
          'games/$indieId.json': const IndexEntry(
            relativePath: 'games/$indieId.json',
            sha256: 'hash_indie_v1',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'drive_indie',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: indieId,
          ),
        },
      );

      final service = TestConfigurableDriveService(
        remoteIndex: remoteIndex,
        remoteFiles: remoteFiles,
      );

      final pullManager = DeltaPullManager(
        driveService: service,
        database: database,
        gameDao: gameDao,
        syncMetaDao: syncMetaDao,
      );

      // Act: Execute Delta Pull
      final report = await pullManager.executeDeltaPull();

      // Assert Pull Execution
      expect(report.isSuccess, isTrue);
      expect(report.downloadedCount, equals(3)); // 3 games
      expect(report.deletedCount, equals(0));

      // 100% Field Preservation Verification on Witcher 3
      final retrieved = await gameDao.getGameById(witcherId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(witcherId));
      expect(retrieved.gameId, equals('292030'));
      expect(retrieved.pluginId, equals('cb91dfa9-9e08-4169-acbe-023a1714d49a'));
      expect(retrieved.name, equals('The Witcher 3: Wild Hunt'));
      expect(retrieved.sortingName, equals('Witcher 3: Wild Hunt, The'));
      expect(retrieved.description, equals('<p>Become a monster slayer for hire.</p>'));
      expect(retrieved.notes, equals('Award-winning dark fantasy masterpiece.'));
      expect(retrieved.playtimeSeconds, equals(432000));
      expect(retrieved.playCount, equals(45));
      expect(retrieved.addedUtc, equals('2020-01-15T10:00:00.000Z'));
      expect(retrieved.modifiedUtc, equals('2026-10-15T18:00:00.000Z'));
      expect(retrieved.lastActivityUtc, equals('2026-10-14T22:30:00.000Z'));
      expect(retrieved.releaseDate, equals('2015-05-19'));
      expect(retrieved.isInstalled, isTrue);
      expect(retrieved.installDirectory, equals(r'D:\Games\Steam\steamapps\common\The Witcher 3'));
      expect(retrieved.installSizeBytes, equals(53687091200));
      expect(retrieved.hidden, isFalse);
      expect(retrieved.favorite, isTrue);
      expect(retrieved.version, equals('4.04'));
      expect(retrieved.userScore, equals(98));
      expect(retrieved.criticScore, equals(93));
      expect(retrieved.communityScore, equals(95));
      expect(retrieved.source?.name, equals('Steam'));
      expect(retrieved.completionStatus?.name, equals('Played'));

      // Taxonomies
      expect(retrieved.platforms.map((e) => e.name), contains('PC (Windows)'));
      expect(retrieved.genres.map((e) => e.name), containsAll(['Role-playing (RPG)', 'Open World']));
      expect(retrieved.developers.map((e) => e.name), contains('CD PROJEKT RED'));
      expect(retrieved.publishers.map((e) => e.name), contains('CD PROJEKT'));
      expect(retrieved.categories.map((e) => e.name), contains('Single-player'));
      expect(retrieved.tags.map((e) => e.name), containsAll(['Fantasy', 'Story Rich']));
      expect(retrieved.features.map((e) => e.name), containsAll(['Cloud Saves', 'Achievements']));
      expect(retrieved.links.map((e) => e.name), containsAll(['Store', 'Wiki']));

      // Media pointers
      expect(retrieved.media.coverDriveFileId, equals('drive_file_witcher_cover_v1'));
      expect(retrieved.media.coverSha256, equals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
      expect(retrieved.media.backgroundDriveFileId, equals('drive_file_witcher_bg'));

      // Normalized Child Tables Verification
      final achievements = await database.db.query('achievements', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(achievements.length, equals(1));
      expect(achievements.first['api_name'], equals('ACH_01'));
      expect(achievements.first['name'], equals('Lilac and Gooseberries'));
      expect(achievements.first['percent'], equals(92.5));
      expect(achievements.first['gamer_score'], equals(15.0));

      final sessions = await database.db.query('play_sessions', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(sessions.length, equals(1));
      expect(sessions.first['elapsed_seconds'], equals(9000));
      expect(sessions.first['action_name'], equals('Play'));

      final hltb = await database.db.query('hltb_data', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(hltb.length, equals(1));
      expect(hltb.first['main_story_seconds'], equals(185400));
      expect(hltb.first['completionist_seconds'], equals(622800));

      final dlcs = await database.db.query('dlc_items', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(dlcs.length, equals(2));
      expect(dlcs.any((d) => d['name'] == 'Hearts of Stone' && d['price'] == 9.99), isTrue);
      expect(dlcs.any((d) => d['name'] == 'Blood and Wine' && d['price'] == 19.99), isTrue);

      // Raw addons JSON preservation
      expect(retrieved.addons['steam_reviews']['review_score_description'], equals('Overwhelmingly Positive'));

      // Search via getFilteredGames with searchQuery
      final searchWitcher = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Witcher'),
        sort: SortOption.titleAsc,
      );
      expect(searchWitcher.map((g) => g.id), contains(witcherId));

      final searchDeveloper = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'PROJEKT'),
        sort: SortOption.titleAsc,
      );
      expect(searchDeveloper.map((g) => g.id), containsAll([witcherId, cyberpunkId]));

      // Multi-criteria Filtering & Sorting
      final filteredFavorites = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(isFavorite: true),
        sort: SortOption.titleAsc,
      );
      expect(filteredFavorites.length, equals(1));
      expect(filteredFavorites.first.id, equals(witcherId));

      final sortedByPlaytime = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(),
        sort: SortOption.playtimeDesc,
      );
      expect(sortedByPlaytime.first.id, equals(witcherId)); // 120 hrs > Cyberpunk 50 hrs
    });

    test('2. Edge Case: Game Deletion (Orphan Pruning) Cascades and Purges Local Records', () async {
      // Step A: Seed initial library with 2 games
      final remoteFiles = <String, String>{
        'manifest.json': jsonEncode(manifestPayload),
        'games/$witcherId.json': jsonEncode(witcherPayload),
        'games/$cyberpunkId.json': jsonEncode(cyberpunkPayload),
      };

      var remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:00:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 2,
        totalEntries: 3,
        totalSizeBytes: 7500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'h_w',
            sizeBytes: 4000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_w',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'h_cp',
            sizeBytes: 2500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
        },
      );

      final service = TestConfigurableDriveService(
        remoteIndex: remoteIndex,
        remoteFiles: remoteFiles,
      );

      final pullManager = DeltaPullManager(
        driveService: service,
        database: database,
        gameDao: gameDao,
        syncMetaDao: syncMetaDao,
      );

      await pullManager.executeDeltaPull();
      expect(await gameDao.getGamesCount(), equals(2));

      // Step B: Simulate C# orphan pruning on desktop: Witcher 3 was uninstalled/deleted from Playnite!
      // In remote sync_index.json, Witcher 3 is completely gone. Only Cyberpunk remains.
      remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:05:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 1,
        totalEntries: 2,
        totalSizeBytes: 3500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:05:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'h_cp',
            sizeBytes: 2500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
        },
      );
      service.remoteIndex = remoteIndex;

      // Act: Delta pull detects remote deletion
      final pruneReport = await pullManager.executeDeltaPull();

      // Assert:
      expect(pruneReport.isSuccess, isTrue);
      expect(pruneReport.downloadedCount, equals(0)); // 0 downloads
      expect(pruneReport.deletedCount, equals(1)); // 1 deleted

      // Witcher 3 must be cascade deleted from games table
      final deletedGame = await gameDao.getGameById(witcherId);
      expect(deletedGame, isNull);

      // Child tables must have zero orphaned records for Witcher 3
      final ach = await database.db.query('achievements', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(ach, isEmpty);
      final ses = await database.db.query('play_sessions', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(ses, isEmpty);
      final hltb = await database.db.query('hltb_data', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(hltb, isEmpty);
      final dlcs = await database.db.query('dlc_items', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(dlcs, isEmpty);

      // Sync entries metadata table pruned
      final syncEntry = await database.db.query('sync_entries', where: 'relative_path = ?', whereArgs: ['games/$witcherId.json']);
      expect(syncEntry, isEmpty);

      // Cyberpunk remains completely intact
      final survivingGame = await gameDao.getGameById(cyberpunkId);
      expect(survivingGame, isNotNull);
      expect(survivingGame!.name, equals('Cyberpunk 2077'));
      expect(await gameDao.getGamesCount(), equals(1));
    });

    test('3. Edge Case: Cover Art Replacement (CAS Hash Change) Triggers Clean Refresh', () async {
      // Initial state with Witcher 3 v1
      final remoteFiles = <String, String>{
        'manifest.json': jsonEncode(manifestPayload),
        'games/$witcherId.json': jsonEncode(witcherPayload),
      };

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:00:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 1,
        totalEntries: 2,
        totalSizeBytes: 5500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'hash_cover_v1',
            sizeBytes: 4500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_w_v1',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
        },
      );

      final service = TestConfigurableDriveService(
        remoteIndex: remoteIndex,
        remoteFiles: remoteFiles,
      );

      final pullManager = DeltaPullManager(
        driveService: service,
        database: database,
        gameDao: gameDao,
        syncMetaDao: syncMetaDao,
      );

      await pullManager.executeDeltaPull();
      final gInitial = (await gameDao.getGameById(witcherId))!;
      expect(gInitial.media.coverSha256, equals('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
      expect(gInitial.media.coverDriveFileId, equals('drive_file_witcher_cover_v1'));

      // Act: User replaced cover in Playnite.
      // C# Exporter recomputed CAS hash and uploaded media/covers/new_cover_hash.webp
      final updatedWitcherPayload = Map<String, dynamic>.from(witcherPayload);
      updatedWitcherPayload['media'] = {
        'cover': {
          'relative_path': 'media/covers/9999999999999999999999999999999999999999999999999999999999999999.webp',
          'sha256': '9999999999999999999999999999999999999999999999999999999999999999',
          'format': 'webp',
          'width': 600,
          'height': 900,
          'drive_file_id': 'drive_file_witcher_cover_v2_new'
        }
      };

      service.remoteFiles['games/$witcherId.json'] = jsonEncode(updatedWitcherPayload);
      service.remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:10:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 1,
        totalEntries: 2,
        totalSizeBytes: 5500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'hash_cover_v2_modified',
            sizeBytes: 4500,
            modifiedUtc: '2026-10-15T18:10:00.000Z',
            driveFileId: 'df_w_v2',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
        },
      );

      final updateReport = await pullManager.executeDeltaPull();
      expect(updateReport.isSuccess, isTrue);
      expect(updateReport.downloadedCount, equals(1));

      // Verify database updated with new cover file ID & hash
      final gUpdated = (await gameDao.getGameById(witcherId))!;
      expect(gUpdated.media.coverSha256, equals('9999999999999999999999999999999999999999999999999999999999999999'));
      expect(gUpdated.media.coverDriveFileId, equals('drive_file_witcher_cover_v2_new'));

      // Verify URL resolver points to new Drive file ID (busting image cache)
      final url = MediaUrlResolver.getDriveThumbnailUrl(gUpdated.media.coverDriveFileId!, width: 300);
      expect(url, contains('drive_file_witcher_cover_v2_new'));
    });

    testWidgets('4. Edge Case: Missing Addons & Unknown Addons Render Gracefully Without Crashing', (tester) async {
      final gameIndie = UnifiedGamePayload.fromJson(indiePayload);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final sections = AddonSectionRegistry.buildAvailableSections(context, gameIndie);
                return ListView(children: sections);
              },
            ),
          ),
        ),
      );

      // Verify FallbackAddonSection rendered for unknown future addon
      expect(find.byType(FallbackAddonSection), findsOneWidget);
      expect(find.text('Future Haptics Addon'), findsOneWidget);
      expect(find.text('Extension Data (future_haptics_addon)'), findsOneWidget);

      // Missing addons (HLTB, Achievements) do not render
      expect(find.text('HowLongToBeat'), findsNothing);
      expect(find.text('Achievements'), findsNothing);
    });

    test('5. Edge Case: Corrupt JSON / Network Interruption Triggers Atomic Rollback with Zero Data Corruption', () async {
      // Initial library with 1 game
      final remoteFiles = <String, String>{
        'manifest.json': jsonEncode(manifestPayload),
        'games/$cyberpunkId.json': jsonEncode(cyberpunkPayload),
      };

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:00:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 1,
        totalEntries: 2,
        totalSizeBytes: 3500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'h_cp',
            sizeBytes: 2500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
        },
      );

      final service = TestConfigurableDriveService(
        remoteIndex: remoteIndex,
        remoteFiles: remoteFiles,
      );

      final pullManager = DeltaPullManager(
        driveService: service,
        database: database,
        gameDao: gameDao,
        syncMetaDao: syncMetaDao,
      );

      await pullManager.executeDeltaPull();
      expect(await gameDao.getGamesCount(), equals(1));

      // Now add Witcher 3, but inject corrupt JSON into the download
      service.remoteFiles['games/$witcherId.json'] = 'corrupt content';
      service.corruptFilePath = 'games/$witcherId.json';
      service.remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:05:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 2,
        totalEntries: 3,
        totalSizeBytes: 7500,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'h_cp',
            sizeBytes: 2500,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'h_w_corrupt',
            sizeBytes: 4000,
            modifiedUtc: '2026-10-15T18:05:00.000Z',
            driveFileId: 'df_w_corrupt',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
        },
      );

      // Act: Delta pull fails during download
      final failureReport = await pullManager.executeDeltaPull();

      // Assert:
      expect(failureReport.isSuccess, isFalse);
      expect(failureReport.errorMessage, contains('FormatException'));

      // Crucial: Atomic rollback validation
      // Games count must remain exactly 1 (Cyberpunk), NOT 2 or corrupted
      expect(await gameDao.getGamesCount(), equals(1));
      final cpAfterFail = await gameDao.getGameById(cyberpunkId);
      expect(cpAfterFail, isNotNull);
      expect(await gameDao.getGameById(witcherId), isNull);

      // Sync entries must not record Witcher 3
      final witcherEntry = await database.db.query('sync_entries', where: 'game_id = ?', whereArgs: [witcherId]);
      expect(witcherEntry, isEmpty);
    });

    test('6. Edge Case: Offline Mode Operates with 100% Fidelity and Zero Network Connectivity', () async {
      // Precondition: Seed library with 2 games
      final remoteFiles = <String, String>{
        'manifest.json': jsonEncode(manifestPayload),
        'games/$witcherId.json': jsonEncode(witcherPayload),
        'games/$cyberpunkId.json': jsonEncode(cyberpunkPayload),
      };

      final remoteIndex = SyncIndex(
        version: '1.0.0',
        generator: 'playnite-exporter-plugin',
        generatedAtUtc: '2026-10-15T18:00:00.000Z',
        libraryId: 'test-library-guid',
        totalGames: 2,
        totalEntries: 3,
        totalSizeBytes: 7000,
        entries: {
          'manifest.json': const IndexEntry(
            relativePath: 'manifest.json',
            sha256: 'h_m',
            sizeBytes: 1000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_m',
            mimeType: 'application/json',
            category: 'manifest',
          ),
          'games/$witcherId.json': const IndexEntry(
            relativePath: 'games/$witcherId.json',
            sha256: 'h_w',
            sizeBytes: 4000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_w',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: witcherId,
          ),
          'games/$cyberpunkId.json': const IndexEntry(
            relativePath: 'games/$cyberpunkId.json',
            sha256: 'h_cp',
            sizeBytes: 2000,
            modifiedUtc: '2026-10-15T18:00:00.000Z',
            driveFileId: 'df_cp',
            mimeType: 'application/json',
            category: 'game_metadata',
            gameId: cyberpunkId,
          ),
        },
      );

      final service = TestConfigurableDriveService(
        remoteIndex: remoteIndex,
        remoteFiles: remoteFiles,
      );

      final pullManager = DeltaPullManager(
        driveService: service,
        database: database,
        gameDao: gameDao,
        syncMetaDao: syncMetaDao,
      );

      await pullManager.executeDeltaPull();

      // Simulate entering airplane mode / complete network outage
      service.simulateNetworkFailure = true;

      // Sync attempt returns clean failure report without crashing the app
      final offlineReport = await pullManager.executeDeltaPull();
      expect(offlineReport.isSuccess, isFalse);
      expect(offlineReport.errorMessage, contains('Simulated network failure'));

      // All local queries, searches, and details work perfectly offline
      final offlineWitcher = await gameDao.getGameById(witcherId);
      expect(offlineWitcher, isNotNull);
      expect(offlineWitcher!.name, equals('The Witcher 3: Wild Hunt'));
      expect(offlineWitcher.playtimeSeconds, equals(432000));

      final offlineCyberpunk = await gameDao.getGameById(cyberpunkId);
      expect(offlineCyberpunk, isNotNull);
      expect(offlineCyberpunk!.name, equals('Cyberpunk 2077'));

      final offlineSearch = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(searchQuery: 'Night City'),
        sort: SortOption.titleAsc,
      );
      expect(offlineSearch.length, equals(1));
      expect(offlineSearch.first.id, equals(cyberpunkId));

      final offlineFilter = await gameDao.getFilteredGames(
        criteria: const GameFilterCriteria(isInstalled: true),
        sort: SortOption.titleAsc,
      );
      expect(offlineFilter.length, equals(2));
    });
  });
}
