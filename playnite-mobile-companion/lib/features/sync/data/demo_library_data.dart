import 'dart:convert';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

/// Provides authoritative offline demo dataset (Cyberpunk 2077, Witcher 3, Elden Ring, Encased)
/// with full rich metadata and addons (achievements, HowLongToBeat, play sessions, DLCs, reviews).
class DemoLibraryData {
  DemoLibraryData._();

  static const String cyberpunkId = '008977a8-b225-4709-b96d-41ac44bef1c3';
  static const String witcherId = '008dd993-7507-4795-b1bb-862f9ce592be';
  static const String eldenRingId = '01a54b98-653e-4361-bd8d-294b00cb3e21';
  static const String encasedId = '028b0561-1250-4bc3-9fc7-789a6a84cf90';

  /// Returns 4 rich demo games with all addon sections populated.
  static List<UnifiedGamePayload> getDemoGames() {
    final now = DateTime.now().toUtc();

    return [
      // 1. Cyberpunk 2077
      UnifiedGamePayload(
        id: cyberpunkId,
        gameId: '1091500',
        pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
        name: 'Cyberpunk 2077',
        sortingName: 'Cyberpunk 2077',
        description:
            '<p>Cyberpunk 2077 is an open-world, action-adventure RPG set in the megalopolis of Night City, where you play as a cyberpunk mercenary wrapped up in a do-or-die fight for survival.</p>',
        notes: 'RTX Overdrive enabled with full path tracing benchmark.',
        playtimeSeconds: 756000, // 210 hours
        playCount: 48,
        addedUtc: '2020-12-10T12:00:00.000Z',
        modifiedUtc: now.subtract(const Duration(hours: 4)).toIso8601String(),
        lastActivityUtc: now.subtract(const Duration(hours: 4)).toIso8601String(),
        recentActivityUtc: now.subtract(const Duration(hours: 4)).toIso8601String(),
        releaseDate: '2020-12-10',
        isInstalled: true,
        installDirectory: r'D:\Games\Steam\steamapps\common\Cyberpunk 2077',
        installSizeBytes: 75161927680,
        favorite: true,
        userScore: 92,
        criticScore: 86,
        communityScore: 89,
        version: '2.12',
        source: const NamedItem(id: 'steam', name: 'Steam'),
        completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
        platforms: const [NamedItem(id: 'pc_win', name: 'PC (Windows)')],
        genres: const [
          NamedItem(id: 'rpg', name: 'Role-playing (RPG)'),
          NamedItem(id: 'action', name: 'Action'),
          NamedItem(id: 'open_world', name: 'Open World'),
        ],
        categories: const [NamedItem(id: 'sp', name: 'Single-player')],
        tags: const [
          NamedItem(id: 'cyberpunk', name: 'Cyberpunk'),
          NamedItem(id: 'scifi', name: 'Sci-fi'),
          NamedItem(id: 'story', name: 'Story Rich'),
        ],
        developers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        publishers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        features: const [
          NamedItem(id: 'ach', name: 'Achievements'),
          NamedItem(id: 'cloud', name: 'Cloud Saves'),
        ],
        links: const [
          LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/1091500/'),
        ],
        media: const MediaPayload(
          coverDriveFileId: 'mock_cover_cyberpunk',
          backgroundDriveFileId: 'mock_bg_cyberpunk',
        ),
        addons: {
          'success_story': {
            'total': 44,
            'unlocked': 35,
            'achievements': [
              {
                'api_name': 'ACH_CP_01',
                'name': 'The World',
                'description': 'Complete the main storyline.',
                'url_unlocked': 'https://cdn.steam.com/cp_ach_01.png',
                'date_unlocked_utc': '2026-08-15T22:30:00Z',
                'percent': 38.2,
                'gamer_score': 50.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_CP_02',
                'name': 'City Runner',
                'description': 'Complete all gigs and NCPD scanner hustles in Watson.',
                'url_unlocked': 'https://cdn.steam.com/cp_ach_02.png',
                'date_unlocked_utc': '2026-07-20T19:15:00Z',
                'percent': 24.1,
                'gamer_score': 30.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_CP_03',
                'name': 'Legend of the Afterlife',
                'description': 'Reach maximum Street Cred.',
                'url_unlocked': 'https://cdn.steam.com/cp_ach_03.png',
                'date_unlocked_utc': '2026-05-10T14:00:00Z',
                'percent': 52.8,
                'gamer_score': 30.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_CP_04',
                'name': 'Breathtaking',
                'description': 'Collect all items that once belonged to Johnny Silverhand.',
                'url_locked': 'https://cdn.steam.com/cp_ach_04_locked.png',
                'percent': 18.5,
                'gamer_score': 40.0,
                'is_hidden': false,
              },
            ],
          },
          'how_long_to_beat': {
            'hltb_id': '2127',
            'main_story_seconds': 90000, // 25h
            'main_extra_seconds': 216000, // 60h
            'completionist_seconds': 374400, // 104h
            'all_styles_seconds': 226800, // 63h
            'url': 'https://howlongtobeat.com/game/2127',
          },
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': now.subtract(const Duration(hours: 4)).toIso8601String(),
                'elapsed_seconds': 12600,
                'action_name': 'Play',
              },
              {
                'date_session_utc': now.subtract(const Duration(days: 2)).toIso8601String(),
                'elapsed_seconds': 7200,
                'action_name': 'Play',
              },
              {
                'date_session_utc': now.subtract(const Duration(days: 6)).toIso8601String(),
                'elapsed_seconds': 10800,
                'action_name': 'Play',
              },
            ],
          },
          'check_dlc': {
            'dlcs': [
              {
                'dlc_id': '2138330',
                'name': 'Cyberpunk 2077: Phantom Liberty',
                'is_owned': true,
                'price': 29.99,
                'currency': 'USD',
                'url': 'https://store.steampowered.com/app/2138330',
              },
            ],
          },
          'steam_reviews': {
            'review_score': 9,
            'review_score_description': 'Very Positive',
            'positive_count': 654200,
            'negative_count': 81200,
          },
        },
      ),

      // 2. The Witcher 3: Wild Hunt
      UnifiedGamePayload(
        id: witcherId,
        gameId: '292030',
        pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
        name: 'The Witcher 3: Wild Hunt',
        sortingName: 'Witcher 3: Wild Hunt, The',
        description:
            '<p>You are Geralt of Rivia, mercenary monster slayer. Before you stands a war-torn, monster-infested continent you can explore at will.</p>',
        notes: 'Award-winning dark fantasy masterpiece. Death March completed.',
        playtimeSeconds: 666000, // 185 hours
        playCount: 35,
        addedUtc: '2015-05-18T10:00:00.000Z',
        modifiedUtc: now.subtract(const Duration(days: 5)).toIso8601String(),
        lastActivityUtc: now.subtract(const Duration(days: 5)).toIso8601String(),
        recentActivityUtc: now.subtract(const Duration(days: 5)).toIso8601String(),
        releaseDate: '2015-05-18',
        isInstalled: true,
        installSizeBytes: 53687091200,
        favorite: true,
        userScore: 96,
        criticScore: 93,
        communityScore: 97,
        version: '4.04',
        source: const NamedItem(id: 'steam', name: 'Steam'),
        completionStatus: const NamedItem(id: 'completed', name: 'Completed'),
        platforms: const [NamedItem(id: 'pc_win', name: 'PC (Windows)')],
        genres: const [
          NamedItem(id: 'rpg', name: 'Role-playing (RPG)'),
          NamedItem(id: 'open_world', name: 'Open World'),
        ],
        categories: const [NamedItem(id: 'sp', name: 'Single-player')],
        tags: const [
          NamedItem(id: 'fantasy', name: 'Dark Fantasy'),
          NamedItem(id: 'story', name: 'Story Rich'),
        ],
        developers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        publishers: const [NamedItem(id: 'cdpr', name: 'CD PROJEKT RED')],
        features: const [
          NamedItem(id: 'ach', name: 'Achievements'),
          NamedItem(id: 'cloud', name: 'Cloud Saves'),
        ],
        links: const [
          LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/292030/'),
        ],
        media: const MediaPayload(
          coverDriveFileId: 'mock_cover_witcher',
          backgroundDriveFileId: 'mock_bg_witcher',
        ),
        addons: {
          'success_story': {
            'total': 78,
            'unlocked': 65,
            'achievements': [
              {
                'api_name': 'ACH_W3_01',
                'name': 'Lilac and Gooseberries',
                'description': 'Find Yennefer of Vengerberg.',
                'url_unlocked': 'https://cdn.steam.com/w3_ach_01.png',
                'date_unlocked_utc': '2020-01-16T14:22:00Z',
                'percent': 92.5,
                'gamer_score': 15.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_W3_02',
                'name': 'Family Counselor',
                'description': 'Find the baron\'s wife and daughter.',
                'url_unlocked': 'https://cdn.steam.com/w3_ach_02.png',
                'date_unlocked_utc': '2020-02-01T18:40:00Z',
                'percent': 71.4,
                'gamer_score': 20.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_W3_03',
                'name': 'Passed the Trial',
                'description': 'Finish the game on any difficulty.',
                'url_unlocked': 'https://cdn.steam.com/w3_ach_03.png',
                'date_unlocked_utc': '2020-04-12T21:00:00Z',
                'percent': 42.0,
                'gamer_score': 40.0,
                'is_hidden': false,
              },
            ],
          },
          'how_long_to_beat': {
            'hltb_id': '10232',
            'main_story_seconds': 185400, // 51.5h
            'main_extra_seconds': 367200, // 102h
            'completionist_seconds': 622800, // 173h
            'all_styles_seconds': 374400, // 104h
            'url': 'https://howlongtobeat.com/game/10232',
          },
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': now.subtract(const Duration(days: 5)).toIso8601String(),
                'elapsed_seconds': 14400,
                'action_name': 'Play',
              },
              {
                'date_session_utc': now.subtract(const Duration(days: 9)).toIso8601String(),
                'elapsed_seconds': 9000,
                'action_name': 'Play',
              },
            ],
          },
          'check_dlc': {
            'dlcs': [
              {
                'dlc_id': '378648',
                'name': 'Hearts of Stone',
                'is_owned': true,
                'price': 9.99,
                'currency': 'USD',
                'url': 'https://store.steampowered.com/app/378648',
              },
              {
                'dlc_id': '378649',
                'name': 'Blood and Wine',
                'is_owned': true,
                'price': 19.99,
                'currency': 'USD',
                'url': 'https://store.steampowered.com/app/378649',
              },
            ],
          },
          'steam_reviews': {
            'review_score': 10,
            'review_score_description': 'Overwhelmingly Positive',
            'positive_count': 735000,
            'negative_count': 21000,
          },
        },
      ),

      // 3. Elden Ring
      UnifiedGamePayload(
        id: eldenRingId,
        gameId: '1245620',
        pluginId: 'cb91dfc9-b977-43bf-8e70-55f46e410fad',
        name: 'Elden Ring',
        sortingName: 'Elden Ring',
        description:
            '<p>THE NEW FANTASY ACTION RPG. Rise, Tarnished, and be guided by grace to brandish the power of the Elden Ring and become an Elden Lord in the Lands Between.</p>',
        notes: 'Defeated Malenia solo with colossal greatsword.',
        playtimeSeconds: 511200, // 142 hours
        playCount: 29,
        addedUtc: '2022-02-25T10:00:00.000Z',
        modifiedUtc: now.subtract(const Duration(days: 14)).toIso8601String(),
        lastActivityUtc: now.subtract(const Duration(days: 14)).toIso8601String(),
        recentActivityUtc: now.subtract(const Duration(days: 14)).toIso8601String(),
        releaseDate: '2022-02-25',
        isInstalled: false,
        favorite: true,
        userScore: 95,
        criticScore: 96,
        communityScore: 94,
        source: const NamedItem(id: 'steam', name: 'Steam'),
        completionStatus: const NamedItem(id: 'beaten', name: 'Beaten'),
        platforms: const [NamedItem(id: 'pc_win', name: 'PC (Windows)')],
        genres: const [
          NamedItem(id: 'action', name: 'Action'),
          NamedItem(id: 'rpg', name: 'Role-playing (RPG)'),
        ],
        categories: const [NamedItem(id: 'sp', name: 'Single-player')],
        tags: const [
          NamedItem(id: 'souls', name: 'Souls-like'),
          NamedItem(id: 'dark_fantasy', name: 'Dark Fantasy'),
        ],
        developers: const [NamedItem(id: 'fromsoft', name: 'FromSoftware Inc.')],
        publishers: const [NamedItem(id: 'bandai', name: 'Bandai Namco Entertainment')],
        links: const [
          LinkItem(name: 'Steam Store', url: 'https://store.steampowered.com/app/1245620/'),
        ],
        media: const MediaPayload(coverDriveFileId: 'mock_cover_eldenring'),
        addons: {
          'success_story': {
            'total': 42,
            'unlocked': 38,
            'achievements': [
              {
                'api_name': 'ACH_ER_01',
                'name': 'Elden Lord',
                'description': 'Achieved the "Elden Lord" ending.',
                'url_unlocked': 'https://cdn.steam.com/er_ach_01.png',
                'date_unlocked_utc': '2022-04-10T23:15:00Z',
                'percent': 35.8,
                'gamer_score': 50.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_ER_02',
                'name': 'Shardbearer Malenia',
                'description': 'Defeated Shardbearer Malenia.',
                'url_unlocked': 'https://cdn.steam.com/er_ach_02.png',
                'date_unlocked_utc': '2022-04-05T17:45:00Z',
                'percent': 34.6,
                'gamer_score': 40.0,
                'is_hidden': false,
              },
            ],
          },
          'how_long_to_beat': {
            'hltb_id': '68151',
            'main_story_seconds': 212400, // 59h
            'main_extra_seconds': 360000, // 100h
            'completionist_seconds': 486000, // 135h
            'all_styles_seconds': 396000, // 110h
            'url': 'https://howlongtobeat.com/game/68151',
          },
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': now.subtract(const Duration(days: 14)).toIso8601String(),
                'elapsed_seconds': 10800,
                'action_name': 'Play',
              },
            ],
          },
          'check_dlc': {
            'dlcs': [
              {
                'dlc_id': '2778580',
                'name': 'Shadow of the Erdtree',
                'is_owned': true,
                'price': 39.99,
                'currency': 'USD',
                'url': 'https://store.steampowered.com/app/2778580',
              },
            ],
          },
          'steam_reviews': {
            'review_score': 9,
            'review_score_description': 'Very Positive',
            'positive_count': 590000,
            'negative_count': 48000,
          },
        },
      ),

      // 4. Encased: A Sci-Fi Post-Apocalyptic RPG
      UnifiedGamePayload(
        id: encasedId,
        gameId: 'encased_epic',
        pluginId: '00000002-0000-0000-0000-000000000002',
        name: 'Encased: A Sci-Fi Post-Apocalyptic RPG',
        sortingName: 'Encased: A Sci-Fi Post-Apocalyptic RPG',
        description:
            '<p>A tactical sci-fi RPG set in an alternative 1970s, where an enormous and inexplicable artifact — the Dome — is discovered in a remote desert.</p>',
        notes: 'Classic isometric CRPG reminiscent of early Fallout.',
        playtimeSeconds: 93600, // 26 hours
        playCount: 12,
        addedUtc: '2021-09-07T10:00:00.000Z',
        modifiedUtc: now.subtract(const Duration(days: 30)).toIso8601String(),
        lastActivityUtc: now.subtract(const Duration(days: 30)).toIso8601String(),
        recentActivityUtc: now.subtract(const Duration(days: 30)).toIso8601String(),
        releaseDate: '2021-09-07',
        isInstalled: true,
        installSizeBytes: 18874368000,
        favorite: false,
        userScore: 82,
        criticScore: 76,
        communityScore: 78,
        source: const NamedItem(id: 'epic', name: 'Epic Games'),
        completionStatus: const NamedItem(id: 'playing', name: 'Playing'),
        platforms: const [NamedItem(id: 'pc_win', name: 'PC (Windows)')],
        genres: const [
          NamedItem(id: 'rpg', name: 'Role-playing (RPG)'),
          NamedItem(id: 'turn_based', name: 'Turn-Based Strategy'),
        ],
        developers: const [NamedItem(id: 'dark_crystal', name: 'Dark Crystal Games')],
        publishers: const [NamedItem(id: 'prime_matter', name: 'Prime Matter')],
        media: const MediaPayload(coverDriveFileId: 'mock_cover_encased'),
        addons: {
          'success_story': {
            'total': 30,
            'unlocked': 15,
            'achievements': [
              {
                'api_name': 'ACH_ENC_01',
                'name': 'Welcome to the Dome',
                'description': 'Enter the Dome for the first time.',
                'url_unlocked': 'https://cdn.steam.com/enc_ach_01.png',
                'date_unlocked_utc': '2021-09-10T12:00:00Z',
                'percent': 95.0,
                'gamer_score': 10.0,
                'is_hidden': false,
              },
              {
                'api_name': 'ACH_ENC_02',
                'name': 'Silver Wing Scholar',
                'description': 'Complete the Silver Wing orientation.',
                'url_unlocked': 'https://cdn.steam.com/enc_ach_02.png',
                'date_unlocked_utc': '2021-09-15T15:30:00Z',
                'percent': 68.0,
                'gamer_score': 15.0,
                'is_hidden': false,
              },
            ],
          },
          'how_long_to_beat': {
            'hltb_id': '70284',
            'main_story_seconds': 97200, // 27h
            'main_extra_seconds': 154800, // 43h
            'completionist_seconds': 248400, // 69h
            'all_styles_seconds': 147600, // 41h
            'url': 'https://howlongtobeat.com/game/70284',
          },
          'game_activity': {
            'sessions': [
              {
                'date_session_utc': now.subtract(const Duration(days: 30)).toIso8601String(),
                'elapsed_seconds': 10800,
                'action_name': 'Play',
              },
            ],
          },
        },
      ),
    ];
  }

  /// Returns summary manifest matching the demo library.
  static Map<String, dynamic> getDemoManifest() {
    return {
      'version': '1.0.0',
      'generated_at_utc': '2026-10-16T12:00:00.000Z',
      'library_summary': {
        'total_games': 4,
        'installed_games': 3,
        'favorite_games': 3,
        'hidden_games': 0,
        'total_playtime_seconds': 2026800,
        'total_play_count': 124,
      },
      'sources': [
        {'id': 'steam', 'name': 'Steam'},
        {'id': 'epic', 'name': 'Epic Games'},
      ],
      'completion_statuses': [
        {'id': 'completed', 'name': 'Completed'},
        {'id': 'beaten', 'name': 'Beaten'},
        {'id': 'playing', 'name': 'Playing'},
      ],
    };
  }

  /// Builds a fully functional MockDriveService preloaded with all 4 games
  /// and valid sync_index.json entries so delta pull succeeds seamlessly.
  static MockDriveService createDemoDriveService() {
    final games = getDemoGames();
    final manifest = getDemoManifest();

    final entriesMap = <String, IndexEntry>{
      'manifest.json': const IndexEntry(
        relativePath: 'manifest.json',
        sha256: 'hash_demo_manifest',
        sizeBytes: 1500,
        modifiedUtc: '2026-10-16T12:00:00.000Z',
        driveFileId: 'mock_demo_manifest',
        mimeType: 'application/json',
        category: 'manifest',
      ),
    };

    final mockFiles = <String, String>{
      'manifest.json': jsonEncode(manifest),
      'mock_demo_manifest': jsonEncode(manifest),
    };

    for (final game in games) {
      final path = 'games/${game.id}.json';
      final fileId = 'mock_${game.id}';
      final jsonStr = jsonEncode(game.toJson());

      entriesMap[path] = IndexEntry(
        relativePath: path,
        sha256: 'hash_${game.id}',
        sizeBytes: jsonStr.length,
        modifiedUtc: '2026-10-16T12:00:00.000Z',
        driveFileId: fileId,
        mimeType: 'application/json',
        category: 'game_metadata',
        gameId: game.id,
      );

      mockFiles[path] = jsonStr;
      mockFiles[fileId] = jsonStr;
    }

    final syncIndex = SyncIndex(
      version: '1.0.0',
      generator: 'playnite-exporter-plugin',
      generatedAtUtc: '2026-10-16T12:00:00.000Z',
      libraryId: 'demo-library-id',
      totalGames: games.length,
      totalEntries: entriesMap.length,
      totalSizeBytes: mockFiles.values.fold<int>(0, (acc, s) => acc + s.length),
      entries: entriesMap,
    );

    final service = MockDriveService(mockIndex: syncIndex);
    mockFiles.forEach((k, v) => service.setFile(k, v));
    return service;
  }
}
