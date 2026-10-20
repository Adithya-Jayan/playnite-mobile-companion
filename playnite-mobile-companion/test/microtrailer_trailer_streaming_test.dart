import 'dart:io';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/widgets/microtrailer_player.dart';
import 'package:playnite_mobile_companion/features/sync/data/sync_config_repository.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_config.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:playnite_mobile_companion/features/sync/presentation/sync_settings_screen.dart';
import 'package:video_player/video_player.dart';

class FakeVideoPlayerController extends VideoPlayerController {
  bool initializeCalled = false;
  bool playCalled = false;

  FakeVideoPlayerController() : super.networkUrl(Uri.parse('https://example.com/trailer.mp4'));

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 120),
      size: const Size(1920, 1080),
    );
  }

  @override
  Future<void> play() async {
    playCalled = true;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SyncConfigRepository configRepo;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    configRepo = SyncConfigRepository(database);
  });

  tearDown(() async {
    MicrotrailerPlayer.enableInTests = false;
    MicrotrailerPlayer.testControllerFactory = null;
    await database.close();
  });

  group('SyncConfig autoStreamTrailersInHero Serialization Tests', () {
    test('1. SyncConfig defaults autoStreamTrailersInHero to false', () {
      const config = SyncConfig();
      expect(config.autoStreamTrailersInHero, isFalse);
    });

    test('2. SyncConfiguration alias matches SyncConfig type', () {
      const SyncConfiguration cfg1 = SyncConfiguration(autoStreamTrailersInHero: true);
      const SyncConfig cfg2 = SyncConfig(autoStreamTrailersInHero: true);
      expect(cfg1.autoStreamTrailersInHero, isTrue);
      expect(cfg2.autoStreamTrailersInHero, isTrue);
      expect(cfg1, isA<SyncConfig>());
      expect(cfg2, isA<SyncConfiguration>());
    });

    test('3. toJson encodes auto_stream_trailers_in_hero', () {
      const config = SyncConfig(autoStreamTrailersInHero: true);
      final json = config.toJson();
      expect(json['auto_stream_trailers_in_hero'], isTrue);

      const configFalse = SyncConfig(autoStreamTrailersInHero: false);
      final jsonFalse = configFalse.toJson();
      expect(jsonFalse['auto_stream_trailers_in_hero'], isFalse);
    });

    test('4. fromJson parses auto_stream_trailers_in_hero (snake_case)', () {
      final json = {'auto_stream_trailers_in_hero': true};
      final config = SyncConfig.fromJson(json);
      expect(config.autoStreamTrailersInHero, isTrue);

      final jsonFalse = {'auto_stream_trailers_in_hero': false};
      final configFalse = SyncConfig.fromJson(jsonFalse);
      expect(configFalse.autoStreamTrailersInHero, isFalse);
    });

    test('5. fromJson parses autoStreamTrailersInHero (camelCase fallback)', () {
      final json = {'autoStreamTrailersInHero': true};
      final config = SyncConfig.fromJson(json);
      expect(config.autoStreamTrailersInHero, isTrue);
    });

    test('6. fromJson handles string and numeric boolean equivalents', () {
      expect(SyncConfig.fromJson({'auto_stream_trailers_in_hero': 'true'}).autoStreamTrailersInHero, isTrue);
      expect(SyncConfig.fromJson({'auto_stream_trailers_in_hero': '1'}).autoStreamTrailersInHero, isTrue);
      expect(SyncConfig.fromJson({'auto_stream_trailers_in_hero': 1}).autoStreamTrailersInHero, isTrue);
      expect(SyncConfig.fromJson({'auto_stream_trailers_in_hero': 0}).autoStreamTrailersInHero, isFalse);
      expect(SyncConfig.fromJson({'auto_stream_trailers_in_hero': 'false'}).autoStreamTrailersInHero, isFalse);
    });

    test('7. fromJson defaults to false when key is omitted', () {
      final config = SyncConfig.fromJson({});
      expect(config.autoStreamTrailersInHero, isFalse);
    });

    test('8. copyWith correctly updates autoStreamTrailersInHero', () {
      const original = SyncConfig(
        googleDriveFolderName: 'CustomSync',
        autoStreamTrailersInHero: false,
      );
      final updated = original.copyWith(autoStreamTrailersInHero: true);
      expect(updated.autoStreamTrailersInHero, isTrue);
      expect(updated.googleDriveFolderName, 'CustomSync');

      final reverted = updated.copyWith(autoStreamTrailersInHero: false);
      expect(reverted.autoStreamTrailersInHero, isFalse);
    });

    test('9. SyncConfigRepository persists and restores autoStreamTrailersInHero', () async {
      final initial = await configRepo.loadConfig();
      expect(initial.autoStreamTrailersInHero, isFalse);

      final updated = initial.copyWith(autoStreamTrailersInHero: true);
      await configRepo.saveConfig(updated);

      final loaded = await configRepo.loadConfig();
      expect(loaded.autoStreamTrailersInHero, isTrue);
    });
  });

  group('SyncSettingsScreen Media / Preferences Switch Tests', () {
    testWidgets('Renders Auto-stream switch with specified label and subtitle, and updates repository', (tester) async {
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
      expect(find.text('Media / Preferences'), findsOneWidget);
      expect(find.text('Auto-stream full trailers in hero banner'), findsOneWidget);
      expect(
        find.text('When disabled, full trailers only play when you tap Watch Trailer to save mobile data'),
        findsOneWidget,
      );

      final switchFinder = find.widgetWithText(SwitchListTile, 'Auto-stream full trailers in hero banner');
      expect(switchFinder, findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(switchFinder);
      expect(switchTile.value, isFalse);

      // Trigger switch change and allow SQLite transaction to complete in background isolate
      await tester.runAsync(() async {
        switchTile.onChanged!(true);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Verify repository updated in SQLite
      late SyncConfiguration savedConfig;
      await tester.runAsync(() async {
        savedConfig = await configRepo.loadConfig();
      });
      expect(savedConfig.autoStreamTrailersInHero, isTrue);
    });
  });

  group('MicrotrailerPlayer On-Demand Streaming Widget Tests', () {
    testWidgets('1. Does NOT initialize or stream full trailer when autoStreamTrailersInHero is false and shows [Watch Trailer] pill', (tester) async {
      bool streamInitiated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_123',
              trailerDriveFileId: 'drive_full_trailer_id',
              autoStreamTrailersInHero: false,
              onTrailerStreamInitiated: () {
                streamInitiated = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Floating pill must be visible
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsOneWidget);
      expect(find.text('Watch Trailer'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      // Stream must NOT be initiated yet
      expect(streamInitiated, isFalse);

      final state = tester.state<MicrotrailerPlayerState>(find.byType(MicrotrailerPlayer));
      expect(state.isStreamInitiated, isFalse);
      expect(state.controller, isNull);
    });

    testWidgets('2. Tapping [Watch Trailer] pill initiates full trailer streaming on demand', (tester) async {
      bool streamInitiated = false;
      final fakeController = FakeVideoPlayerController();

      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) => fakeController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_456',
              trailerWebUrl: 'https://example.com/cinematic_trailer.mp4',
              autoStreamTrailersInHero: false,
              onTrailerStreamInitiated: () {
                streamInitiated = true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Watch Trailer'), findsOneWidget);
      expect(streamInitiated, isFalse);

      // Tap Watch Trailer pill
      await tester.tap(find.text('Watch Trailer'));
      await tester.pump();

      expect(streamInitiated, isTrue);
      final state = tester.state<MicrotrailerPlayerState>(find.byType(MicrotrailerPlayer));
      expect(state.isStreamInitiated, isTrue);

      // Finish async video controller initialization
      await tester.pumpAndSettle();

      expect(fakeController.initializeCalled, isTrue);
      expect(fakeController.playCalled, isTrue);
      expect(state.isVideoInitialized, isTrue);
      // Once initialized and playing, pill is hidden
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
    });

    testWidgets('3. Auto-streams full trailer on mount when autoStreamTrailersInHero is true (no pill)', (tester) async {
      final fakeController = FakeVideoPlayerController();

      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) => fakeController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_789',
              trailerDriveFileId: 'drive_heavy_trailer_id',
              gallerySettings: const GallerySettings(),
              autoStreamTrailersInHero: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // No watch trailer pill should be rendered because auto-stream is enabled
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
      expect(find.text('Watch Trailer'), findsNothing);

      await tester.pumpAndSettle();
      expect(fakeController.initializeCalled, isTrue);
      expect(fakeController.playCalled, isTrue);
    });

    testWidgets('4. Lightweight microtrailer auto-loops on mount even when autoStreamTrailersInHero is false (no pill)', (tester) async {
      final fakeController = FakeVideoPlayerController();

      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) => fakeController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_abc',
              microtrailerDriveFileId: 'microtrailer_drive_id',
              trailerDriveFileId: 'full_heavy_trailer_drive_id',
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Pill should NOT be shown because lightweight microtrailer is available
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
      expect(find.text('Watch Trailer'), findsNothing);

      await tester.pumpAndSettle();
      expect(fakeController.initializeCalled, isTrue);
      expect(fakeController.playCalled, isTrue);
    });

    testWidgets('5. Game with neither microtrailer nor full trailer shows no pill', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_none',
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
      expect(find.text('Watch Trailer'), findsNothing);
    });

    testWidgets('6. Rebuilding with autoStreamTrailersInHero changing from false to true triggers video init', (tester) async {
      final fakeController = FakeVideoPlayerController();
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) => fakeController;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_async_config',
              trailerWebUrl: 'https://example.com/trailer.mp4',
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsOneWidget);
      expect(fakeController.initializeCalled, isFalse);

      // Rebuild with autoStreamTrailersInHero: true (as happens when config loads from SQLite)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_async_config',
              trailerWebUrl: 'https://example.com/trailer.mp4',
              autoStreamTrailersInHero: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeController.initializeCalled, isTrue);
      expect(fakeController.playCalled, isTrue);
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
    });

    testWidgets('7. Cached local trailer file is not auto-played when autoStream is false, shows pill and plays on tap', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('trailer_local_test');
      final trailerFile = File('${tempDir.path}/local_trailer.mp4');
      trailerFile.writeAsBytesSync([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);

      final fakeController = FakeVideoPlayerController();
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) => fakeController;

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MicrotrailerPlayer(
                gameId: 'local_game_test',
                trailerDriveFileId: trailerFile.path,
                autoStreamTrailersInHero: false,
              ),
            ),
          ),
        );
        await tester.pump();

        // Must show watch trailer pill, must NOT auto-play
        expect(find.byKey(const Key('hero_watch_trailer_pill')), findsOneWidget);
        expect(find.text('Watch Trailer'), findsOneWidget);
        expect(fakeController.initializeCalled, isFalse);

        // Tap Watch Trailer
        await tester.tap(find.text('Watch Trailer'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(fakeController.initializeCalled, isTrue);
        expect(fakeController.playCalled, isTrue);
        expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('8. MicrotrailerPlayer does not access or require open AppDatabase instance', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'isolated_game',
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state<MicrotrailerPlayerState>(find.byType(MicrotrailerPlayer));
      expect(state.controller, isNull);
    });
  });
}
