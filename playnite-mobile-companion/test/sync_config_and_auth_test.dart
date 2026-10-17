import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/game_dao.dart';
import 'package:playnite_mobile_companion/core/network/google_drive_api_service.dart';
import 'package:playnite_mobile_companion/core/network/local_folder_drive_service.dart';
import 'package:playnite_mobile_companion/core/network/mock_drive_service.dart';
import 'package:playnite_mobile_companion/core/utils/media_url_resolver.dart';
import 'package:playnite_mobile_companion/features/sync/data/delta_pull_manager.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SyncConfigRepository repo;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    repo = SyncConfigRepository(database);
  });

  tearDown(() async {
    await database.close();
    MediaUrlResolver.setAuthToken(null);
  });

  group('Sync Configuration & Authentication Architecture Tests', () {
    test('1. SyncConfigRepository persists and restores settings in SQLite', () async {
      // Initially default configuration
      final initial = await repo.loadConfig();
      expect(initial.storageType, SyncStorageType.googleDrive);
      expect(initial.googleDriveFolderName, 'PlayniteSync');
      expect(initial.googleAccessToken, isEmpty);

      // Save updated configuration with token and explicit folder ID
      const updated = SyncConfiguration(
        storageType: SyncStorageType.googleDrive,
        googleDriveFolderName: 'CustomSyncFolder',
        googleDriveFolderId: 'folder_abc_123',
        googleClientId: '123456789-test.apps.googleusercontent.com',
        googleAccessToken: 'ya29.sample_oauth_token',
        localFolderPath: '',
      );

      await repo.saveConfig(updated);

      // Verify token updated in MediaUrlResolver
      expect(MediaUrlResolver.authToken, 'ya29.sample_oauth_token');
      expect(MediaUrlResolver.getAuthHeaders()['Authorization'], 'Bearer ya29.sample_oauth_token');

      // Reload from fresh query
      final restored = await repo.loadConfig();
      expect(restored.storageType, SyncStorageType.googleDrive);
      expect(restored.googleDriveFolderName, 'CustomSyncFolder');
      expect(restored.googleDriveFolderId, 'folder_abc_123');
      expect(restored.googleClientId, '123456789-test.apps.googleusercontent.com');
      expect(restored.googleAccessToken, 'ya29.sample_oauth_token');
      expect(restored.isGoogleDriveConfigured, isTrue);
    });

    test('2. SyncConfigRepository creates appropriate DriveApiService for each storage type', () {
      final driveConfig = const SyncConfiguration(
        storageType: SyncStorageType.googleDrive,
        googleDriveFolderName: 'PlayniteSync',
        googleDriveFolderId: 'folder_123',
      );
      final driveService = repo.createDriveService(driveConfig);
      expect(driveService, isA<GoogleDriveApiService>());

      final localConfig = const SyncConfiguration(
        storageType: SyncStorageType.localFolder,
        localFolderPath: '/storage/emulated/0/Download/PlayniteSync',
      );
      final localService = repo.createDriveService(localConfig);
      expect(localService, isA<LocalFolderDriveService>());

      final demoConfig = const SyncConfiguration(
        storageType: SyncStorageType.demo,
      );
      final demoService = repo.createDriveService(demoConfig);
      expect(demoService, isA<MockDriveService>());
      final mock = demoService as MockDriveService;
      expect(mock.mockIndex, isNotNull);
      expect(mock.mockIndex!.totalGames, 4);
      expect(mock.mockFiles.containsKey('manifest.json'), isTrue);
      expect(mock.mockFiles.containsKey('games/008977a8-b225-4709-b96d-41ac44bef1c3.json'), isTrue);
    });

    test('3. LocalFolderDriveService reads local filesystem export files', () async {
      final tempDir = await Directory.systemTemp.createTemp('playnite_test_local_sync');
      try {
        final syncIndexJson = {
          'version': '1.0.0',
          'generator': 'playnite-exporter-plugin',
          'generated_at_utc': '2026-10-16T12:00:00Z',
          'library_id': 'local-test-lib',
          'total_games': 1,
          'total_entries': 1,
          'total_size_bytes': 1500,
          'entries': {
            'games/game-1.json': {
              'sha256': 'hash1',
              'size_bytes': 1500,
              'modified_utc': '2026-10-16T12:00:00Z',
              'drive_file_id': '',
              'mime_type': 'application/json',
              'category': 'game_metadata',
              'game_id': 'game-1',
            }
          }
        };

        final indexFile = File('${tempDir.path}/sync_index.json');
        await indexFile.writeAsString(jsonEncode(syncIndexJson));

        final gamesDir = Directory('${tempDir.path}/games');
        await gamesDir.create();
        final gameFile = File('${gamesDir.path}/game-1.json');
        await gameFile.writeAsString('{"id": "game-1", "name": "Local Game"}');

        final localService = LocalFolderDriveService(tempDir.path);

        final index = await localService.fetchSyncIndex();
        expect(index.totalGames, 1);
        expect(index.entries.containsKey('games/game-1.json'), isTrue);

        final content = await localService.downloadFileText('games/game-1.json');
        expect(content, contains('Local Game'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('4. GoogleDriveApiService.testConnection validates OAuth token and folder', () async {
      MediaUrlResolver.setAuthToken('mock_valid_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/about')) {
          return http.Response(
            jsonEncode({
              'user': {
                'displayName': 'Test User',
                'emailAddress': 'test@gmail.com',
              }
            }),
            200,
          );
        }
        if (request.url.path.contains('/files')) {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'folder_abc', 'name': 'PlayniteSync'},
                {'id': 'file_idx', 'name': 'sync_index.json'},
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GoogleDriveApiService(
        client: mockClient,
        syncFolderName: 'PlayniteSync',
      );

      final result = await service.testConnection();
      expect(result['success'], isTrue);
      expect(result['user'], 'test@gmail.com');
      expect(result['folderId'], 'folder_abc');
    });

    test('5. GoogleDriveApiService.testConnection reports 401 Unauthorized for expired tokens', () async {
      MediaUrlResolver.setAuthToken('expired_token');

      final mockClient = MockClient((request) async {
        return http.Response('{"error": {"code": 401, "message": "Invalid Credentials"}}', 401);
      });

      final service = GoogleDriveApiService(
        client: mockClient,
        syncFolderName: 'PlayniteSync',
      );

      final result = await service.testConnection();
      expect(result['success'], isFalse);
      expect(result['error'], contains('401 Unauthorized'));
    });

    test('6. SyncProgress tracks currentItem and formatted progress details', () {
      const progress = SyncProgress(
        phase: SyncPhase.downloadingPayloads,
        current: 5,
        total: 12,
        bytesDownloaded: 15728640,
        totalBytes: 31457280,
        message: 'Downloading 5/12 games (Cyberpunk 2077)...',
        currentItem: 'Cyberpunk 2077',
      );

      expect(progress.phase, equals(SyncPhase.downloadingPayloads));
      expect(progress.current, equals(5));
      expect(progress.total, equals(12));
      expect(progress.currentItem, equals('Cyberpunk 2077'));
      expect(progress.message, contains('(Cyberpunk 2077)'));

      final updated = progress.copyWith(
        current: 6,
        currentItem: 'The Witcher 3: Wild Hunt',
        message: 'Downloading 6/12 games (The Witcher 3: Wild Hunt)...',
      );
      expect(updated.current, equals(6));
      expect(updated.currentItem, equals('The Witcher 3: Wild Hunt'));
      expect(updated.totalBytes, equals(31457280));
    });

    test('7. DeltaPullManager successfully executes delta pull using Demo storage provider', () async {
      const demoConfig = SyncConfiguration(storageType: SyncStorageType.demo);
      final demoService = repo.createDriveService(demoConfig);

      final gameDao = GameDao(database);
      final pullManager = DeltaPullManager(
        driveService: demoService,
        database: database,
        gameDao: gameDao,
      );

      final report = await pullManager.executeDeltaPull();

      expect(report.isSuccess, isTrue);
      expect(report.downloadedCount, equals(4));

      final gamesCount = await gameDao.getGamesCount();
      expect(gamesCount, equals(4));

      // Verify Cyberpunk 2077 has achievements ingested
      final cyberpunk = await gameDao.getGameById('008977a8-b225-4709-b96d-41ac44bef1c3');
      expect(cyberpunk, isNotNull);
      expect(cyberpunk!.name, equals('Cyberpunk 2077'));
      expect(cyberpunk.playtimeSeconds, equals(756000));
      expect(cyberpunk.addons['how_long_to_beat'], isNotNull);

      // Verify second pull is a no-op
      final secondReport = await pullManager.executeDeltaPull();
      expect(secondReport.isSuccess, isTrue);
      expect(secondReport.downloadedCount, equals(0));
    });
  });
}
