import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/core/database/daos/addon_db_handlers/achievements_db_handler.dart';
import 'package:playnite_mobile_companion/core/utils/achievement_helper.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/addon_registry/sections/achievements_section.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Code Review Fixes Tests', () {
    late AppDatabase database;
    late GallerySettingsRepository galleryRepo;

    setUp(() async {
      database = AppDatabase.instance;
      await database.init(inMemory: true);
      await database.reset();
      galleryRepo = GallerySettingsRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('1. AchievementHelper.isUnlocked handles boolean, numeric, string, and timestamp formats', () {
      // True cases
      expect(AchievementHelper.isUnlocked({'unlocked': true}), isTrue);
      expect(AchievementHelper.isUnlocked({'is_unlocked': true}), isTrue);
      expect(AchievementHelper.isUnlocked({'unlocked': 1}), isTrue);
      expect(AchievementHelper.isUnlocked({'is_unlocked': 1}), isTrue);
      expect(AchievementHelper.isUnlocked({'unlocked': 'true'}), isTrue);
      expect(AchievementHelper.isUnlocked({'is_unlocked': 'true'}), isTrue);
      expect(AchievementHelper.isUnlocked({'date_unlocked_utc': '2026-10-24T12:00:00Z'}), isTrue);
      expect(AchievementHelper.isUnlocked({'date_unlocked': '2026-10-24 12:00:00'}), isTrue);
      expect(AchievementHelper.isUnlocked({'unlock_time_utc': '2026-10-24T12:00:00Z'}), isTrue);

      // False cases
      expect(AchievementHelper.isUnlocked({'unlocked': false}), isFalse);
      expect(AchievementHelper.isUnlocked({'is_unlocked': false}), isFalse);
      expect(AchievementHelper.isUnlocked({'unlocked': 0}), isFalse);
      expect(AchievementHelper.isUnlocked({'unlocked': 'false'}), isFalse);
      expect(AchievementHelper.isUnlocked({'date_unlocked_utc': ''}), isFalse);
      expect(AchievementHelper.isUnlocked({'date_unlocked_utc': '   '}), isFalse);
      expect(AchievementHelper.isUnlocked({}), isFalse);
    });

    test('2. supportedKeys prioritizes playnite_achievements over achievements and success_story', () {
      const expectedKeys = ['playnite_achievements', 'achievements', 'success_story'];
      expect(AchievementsDbHandler.supportedKeys, equals(expectedKeys));
      expect(AchievementsSection.supportedKeys, equals(expectedKeys));
    });

    test('3. GallerySettingsRepository.saveMediaTierSizes accepts MediaTierSizes object without primitive clumps', () async {
      const sizes = MediaTierSizes(
        staticMediaBytes: 1048576,
        microtrailersBytes: 2097152,
        completeOfflineBytes: 5242880,
      );

      await galleryRepo.saveMediaTierSizes(sizes);

      final loaded = await galleryRepo.loadMediaTierSizes();
      expect(loaded.staticMediaBytes, equals(1048576));
      expect(loaded.coversAndFanartsBytes, equals(1048576));
      expect(loaded.microtrailersBytes, equals(2097152));
      expect(loaded.completeOfflineBytes, equals(5242880));
      expect(loaded.staticAndMicrotrailersBytes, equals(1048576 + 2097152));
    });

    test('4. GallerySettingsRepository.saveMediaTierSizes supports optional named parameter overrides', () async {
      const sizes = MediaTierSizes(
        staticMediaBytes: 1000,
        microtrailersBytes: 2000,
        completeOfflineBytes: 3000,
      );

      await galleryRepo.saveMediaTierSizes(
        sizes,
        completeOfflineBytes: 9999,
      );

      final loaded = await galleryRepo.loadMediaTierSizes();
      expect(loaded.staticMediaBytes, equals(1000));
      expect(loaded.microtrailersBytes, equals(2000));
      expect(loaded.completeOfflineBytes, equals(9999));
    });

    testWidgets('5. SyncSettingsScreen prompts cache cleanup on any tier downgrade (e.g. completeOffline to staticMedia)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await galleryRepo.saveSettings(const GallerySettings(mediaStorageTier: MediaStorageTier.completeOffline));
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SyncSettingsScreen(database: database),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final dropdownFinder = find.byKey(const Key('dropdown_mediaStorageTier'));
      final dropdown = tester.widget<DropdownButton<MediaStorageTier>>(dropdownFinder);
      expect(dropdown.value, equals(MediaStorageTier.completeOffline));

      // Downgrade from completeOffline to staticMedia (not cacheOnly)
      await tester.runAsync(() async {
        dropdown.onChanged!(MediaStorageTier.staticMedia);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));

      // Verify downgrade prompt appears with updated text
      expect(find.text('Free Up Storage Space?'), findsOneWidget);
      expect(find.textContaining('You downgraded your media storage tier.'), findsOneWidget);
      expect(find.text('Keep Downloaded Media'), findsOneWidget);
      expect(find.text('Clear & Free Up Space'), findsOneWidget);

      // Tap 'Keep Downloaded Media'
      await tester.tap(find.text('Keep Downloaded Media'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Free Up Storage Space?'), findsNothing);

      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await galleryRepo.loadSettings();
      });
      expect(saved.mediaStorageTier, equals(MediaStorageTier.staticMedia));
    });
  });
}
