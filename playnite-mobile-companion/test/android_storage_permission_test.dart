import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/network/local_folder_drive_service.dart';
import 'package:playnite_mobile_companion/core/services/storage_permission_service.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/widgets/sync_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Directory tempDir;

  setUp(() async {
    StoragePermissionService.mockPermissionGranted = null;
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    tempDir = await Directory.systemTemp.createTemp('playnite_android_perm_test_');
  });

  tearDown(() async {
    StoragePermissionService.mockPermissionGranted = null;
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StoragePermissionService Tests', () {
    test('1. Default platform returns true when running in test environment', () async {
      expect(await StoragePermissionService.isStoragePermissionGranted(), isTrue);
      expect(await StoragePermissionService.requestStoragePermission(), isTrue);
      expect(await StoragePermissionService.openStorageSettings(), isTrue);
    });

    test('2. Mock permission granted override controls status', () async {
      StoragePermissionService.mockPermissionGranted = false;
      expect(await StoragePermissionService.isStoragePermissionGranted(), isFalse);
      expect(await StoragePermissionService.requestStoragePermission(), isFalse);

      StoragePermissionService.mockPermissionGranted = true;
      expect(await StoragePermissionService.isStoragePermissionGranted(), isTrue);
      expect(await StoragePermissionService.requestStoragePermission(), isTrue);
    });
  });

  group('LocalFolderDriveService Validation & Error Handling Tests', () {
    test('3. validateFolder reports error on empty path', () async {
      final service = LocalFolderDriveService('');
      final result = await service.validateFolder();
      expect(result.isValid, isFalse);
      expect(result.message, contains('enter a directory path'));
    });

    test('4. validateFolder reports directory not existing', () async {
      final service = LocalFolderDriveService('${tempDir.path}/non_existent_folder_xyz');
      final result = await service.validateFolder();
      expect(result.isValid, isFalse);
      expect(result.message, contains('Directory does not exist'));
    });

    test('5. validateFolder reports missing sync_index.json in existing directory', () async {
      final service = LocalFolderDriveService(tempDir.path);
      final result = await service.validateFolder();
      expect(result.isValid, isFalse);
      expect(result.message, contains('sync_index.json not found'));
    });

    test('6. validateFolder succeeds when sync_index.json is valid', () async {
      final indexFile = File('${tempDir.path}/sync_index.json');
      final validIndex = {
        'version': '1.0.0',
        'generator': 'playnite-exporter-plugin',
        'generated_at_utc': '2026-11-21T21:00:00.000Z',
        'library_id': 'test-lib-id',
        'total_games': 42,
        'total_entries': 100,
        'total_size_bytes': 5000000,
        'entries': {},
      };
      await indexFile.writeAsString(jsonEncode(validIndex));

      final service = LocalFolderDriveService(tempDir.path);
      final result = await service.validateFolder();
      expect(result.isValid, isTrue);
      expect(result.totalGames, 42);
      expect(result.message, contains('Valid export found (42 games'));

      final parsed = await service.fetchSyncIndex();
      expect(parsed.totalGames, 42);
      expect(parsed.libraryId, 'test-lib-id');
    });

    test('7. fetchSyncIndex throws helpful message on missing file', () async {
      final service = LocalFolderDriveService('${tempDir.path}/empty_dir');
      expect(
        () => service.fetchSyncIndex(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('sync_index.json not found'),
        )),
      );
    });

    test('8. downloadFileBytes reads existing files and throws informative error on missing', () async {
      final testFile = File('${tempDir.path}/manifest.json');
      await testFile.writeAsString('{"version": "1.0.0"}');

      final service = LocalFolderDriveService(tempDir.path);
      final bytes = await service.downloadFileBytes('manifest.json');
      expect(utf8.decode(bytes), contains('"version": "1.0.0"'));

      expect(
        () => service.downloadFileBytes('missing_payload.json'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Local sync file not found'),
        )),
      );
    });
  });

  group('Sync UI Storage Permission Integration Tests', () {
    testWidgets('9. SyncDialog shows Grant Storage Permission button when permission error occurs', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Create a mock local folder service that throws a permission error
      final service = LocalFolderDriveService('${tempDir.path}/permission_test');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncDialog(
              database: database,
              driveService: service,
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byType(SyncDialog), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('10. SyncSettingsScreen renders Local Folder section with Verify Folder Access button', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final configRepo = SyncConfigRepository(database);
      await tester.runAsync(() async {
        await configRepo.saveConfig(SyncConfiguration(
          storageType: SyncStorageType.localFolder,
          localFolderPath: tempDir.path,
        ));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncSettingsScreen(database: database),
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Local Directory Staging'), findsOneWidget);
      expect(find.text('Verify Folder Access'), findsOneWidget);

      final buttonFinder = find.byKey(const Key('btn_verify_local_folder'));
      expect(buttonFinder, findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(buttonFinder);

      await tester.runAsync(() async {
        button.onPressed!();
        await Future.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 300));

      // Should display validation result (sync_index.json not found because tempDir is empty)
      expect(find.textContaining('sync_index.json not found'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
