import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/settings/presentation/gallery_settings_screen.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Ticket #22 Settings Decoupling: SyncSettingsScreen Media Storage Tests', () {
    testWidgets('1. SyncSettingsScreen renders Media Storage & Offline Sync section with default Cache Only tier', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: SyncSettingsScreen(database: database),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.text('Media Storage & Offline Sync'), findsOneWidget);
      expect(find.text('Media Storage Mode'), findsOneWidget);
      expect(find.text('Cache Only (On-demand as you browse library - Default)'), findsOneWidget);

      final dropdownFinder = find.byKey(const Key('dropdown_mediaStorageTier'));
      expect(dropdownFinder, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<MediaStorageTier>>(dropdownFinder);
      expect(dropdown.value, equals(MediaStorageTier.cacheOnly));
      expect(dropdown.items?.length, equals(4));
    });

    testWidgets('2. Upgrading to offline tier prompts Pre-download Media? dialog with Sync Now and Later', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      // Change tier to staticMedia
      await tester.runAsync(() async {
        dropdown.onChanged!(MediaStorageTier.staticMedia);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));

      // Verify upgrade prompt appears
      expect(find.text('Pre-download Media?'), findsOneWidget);
      expect(find.text('Sync Now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);

      // Tap 'Later' to dismiss
      await tester.tap(find.text('Later'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pre-download Media?'), findsNothing);

      // Verify tier saved in repository
      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await galleryRepo.loadSettings();
      });
      expect(saved.mediaStorageTier, equals(MediaStorageTier.staticMedia));
    });

    testWidgets('3. Downgrading to cacheOnly prompts Free Up Storage Space? with Keep Downloaded Media option', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Pre-set repository to staticMedia within runAsync
      await tester.runAsync(() async {
        await galleryRepo.saveSettings(const GallerySettings(mediaStorageTier: MediaStorageTier.staticMedia));
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

      expect(find.text('Static Media (Covers, Backgrounds, Logos, Banners - ~1.28 GB est.)'), findsOneWidget);

      final dropdownFinder = find.byKey(const Key('dropdown_mediaStorageTier'));
      final dropdown = tester.widget<DropdownButton<MediaStorageTier>>(dropdownFinder);

      // Downgrade to cacheOnly
      await tester.runAsync(() async {
        dropdown.onChanged!(MediaStorageTier.cacheOnly);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));

      // Verify downgrade prompt appears
      expect(find.text('Free Up Storage Space?'), findsOneWidget);
      expect(find.text('Keep Downloaded Media'), findsOneWidget);
      expect(find.text('Clear & Free Up Space'), findsOneWidget);

      // Tap 'Keep Downloaded Media'
      await tester.tap(find.text('Keep Downloaded Media'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Free Up Storage Space?'), findsNothing);

      // Verify tier saved in repository as cacheOnly
      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await galleryRepo.loadSettings();
      });
      expect(saved.mediaStorageTier, equals(MediaStorageTier.cacheOnly));
    });

    testWidgets('4. Downgrading to cacheOnly and choosing Clear & Free Up Space clears cache', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await galleryRepo.saveSettings(const GallerySettings(mediaStorageTier: MediaStorageTier.staticMedia));
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

      await tester.runAsync(() async {
        dropdown.onChanged!(MediaStorageTier.cacheOnly);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Free Up Storage Space?'), findsOneWidget);

      // Tap 'Clear & Free Up Space'
      await tester.tap(find.text('Clear & Free Up Space'));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Free Up Storage Space?'), findsNothing);

      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await galleryRepo.loadSettings();
      });
      expect(saved.mediaStorageTier, equals(MediaStorageTier.cacheOnly));
    });
  });

  group('Ticket #22 Settings Decoupling: GallerySettingsScreen Decoupling Tests', () {
    testWidgets('1. GallerySettingsScreen renders display preferences and video priority without media storage dropdown', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: GallerySettingsScreen(database: database),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Display preferences
      expect(find.text('Display Preferences'), findsOneWidget);
      expect(find.text('Default View Mode'), findsOneWidget);
      expect(find.text('Rating Score Source'), findsOneWidget);

      // Video playback priority
      expect(find.text('Video Playback & Fallback Priority'), findsOneWidget);
      expect(find.text('MiniTrailer (Microtrailer)'), findsOneWidget);
      expect(find.text('HQ Video (Full Trailer)'), findsOneWidget);
      expect(find.text('Online Stream (Steam CDN)'), findsOneWidget);

      // Pointer tile present
      expect(find.text('Media Storage & Offline Sync'), findsOneWidget);
      expect(find.text('Media download policy is configured in Sync & Storage Settings'), findsOneWidget);

      // REDUNDANT MEDIA STORAGE DROPDOWN IS ABSENT
      expect(find.byKey(const Key('dropdown_mediaStorageTier')), findsNothing);
      expect(find.byType(DropdownButton<MediaStorageTier>), findsNothing);
    });

    testWidgets('2. Tapping pointer tile in GallerySettingsScreen navigates to SyncSettingsScreen', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: GallerySettingsScreen(database: database),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final pointerTile = find.widgetWithText(ListTile, 'Media Storage & Offline Sync');
      expect(pointerTile, findsOneWidget);

      await tester.tap(pointerTile);
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));

      // Now we should be on SyncSettingsScreen
      expect(find.byType(SyncSettingsScreen), findsOneWidget);
      expect(find.text('Sync & Storage Settings'), findsOneWidget);
      expect(find.byKey(const Key('dropdown_mediaStorageTier')), findsOneWidget);
    });
  });
}
