import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playnite_mobile_companion/core/database/app_database.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/game_detail_screen.dart';
import 'package:playnite_mobile_companion/features/game_detail/presentation/widgets/microtrailer_player.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';
import 'package:playnite_mobile_companion/features/settings/presentation/gallery_settings_screen.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import 'package:video_player/video_player.dart';

class FakeVideoPlayerController extends VideoPlayerController {
  bool initializeCalled = false;
  bool playCalled = false;
  Uri? lastUri;

  FakeVideoPlayerController(super.url)
      : lastUri = url,
        super.networkUrl();

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 90),
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
  late GallerySettingsRepository repo;

  setUp(() async {
    database = AppDatabase.instance;
    await database.init(inMemory: true);
    await database.reset();
    repo = GallerySettingsRepository(database);
  });

  tearDown(() async {
    MicrotrailerPlayer.enableInTests = false;
    MicrotrailerPlayer.testControllerFactory = null;
    await database.close();
  });

  group('GallerySettings Video Playback Priority Data Model Tests', () {
    test('1. Default GallerySettings contains expected priority and enable flags', () {
      const settings = GallerySettings();

      expect(settings.videoPlaybackPriority, equals([
        VideoSourceType.miniTrailer,
        VideoSourceType.hqVideo,
        VideoSourceType.onlineStream,
      ]));
      expect(settings.enableMiniTrailers, isTrue);
      expect(settings.enableHqVideos, isTrue);
      expect(settings.enableOnlineStream, isFalse);
    });

    test('2. toJson serializes video playback priority and toggles correctly', () {
      const settings = GallerySettings(
        videoPlaybackPriority: [
          VideoSourceType.hqVideo,
          VideoSourceType.onlineStream,
          VideoSourceType.miniTrailer,
        ],
        enableMiniTrailers: false,
        enableHqVideos: true,
        enableOnlineStream: true,
      );

      final json = settings.toJson();
      expect(json['videoPlaybackPriority'], equals(['hqVideo', 'onlineStream', 'miniTrailer']));
      expect(json['enableMiniTrailers'], isFalse);
      expect(json['enableHqVideos'], isTrue);
      expect(json['enableOnlineStream'], isTrue);
    });

    test('3. fromJson deserializes video playback priority and flags', () {
      final json = {
        'videoPlaybackPriority': ['onlineStream', 'miniTrailer', 'hqVideo'],
        'enableMiniTrailers': false,
        'enableHqVideos': false,
        'enableOnlineStream': true,
      };

      final settings = GallerySettings.fromJson(json);
      expect(settings.videoPlaybackPriority, equals([
        VideoSourceType.onlineStream,
        VideoSourceType.miniTrailer,
        VideoSourceType.hqVideo,
      ]));
      expect(settings.enableMiniTrailers, isFalse);
      expect(settings.enableHqVideos, isFalse);
      expect(settings.enableOnlineStream, isTrue);
    });

    test('4. fromJson fills in missing enum entries or invalid names safely', () {
      final jsonPartial = {
        'videoPlaybackPriority': ['onlineStream', 'nonExistentSource'],
      };

      final settings = GallerySettings.fromJson(jsonPartial);
      expect(settings.videoPlaybackPriority.first, equals(VideoSourceType.onlineStream));
      expect(settings.videoPlaybackPriority.contains(VideoSourceType.miniTrailer), isTrue);
      expect(settings.videoPlaybackPriority.contains(VideoSourceType.hqVideo), isTrue);
      expect(settings.videoPlaybackPriority.length, equals(3));
      expect(settings.enableMiniTrailers, isTrue);
      expect(settings.enableHqVideos, isTrue);
      expect(settings.enableOnlineStream, isFalse);
    });

    test('5. copyWith properly updates video playback priority and toggles', () {
      const initial = GallerySettings();
      final updated = initial.copyWith(
        videoPlaybackPriority: [
          VideoSourceType.onlineStream,
          VideoSourceType.hqVideo,
          VideoSourceType.miniTrailer,
        ],
        enableMiniTrailers: false,
        enableHqVideos: false,
        enableOnlineStream: true,
      );

      expect(updated.videoPlaybackPriority, equals([
        VideoSourceType.onlineStream,
        VideoSourceType.hqVideo,
        VideoSourceType.miniTrailer,
      ]));
      expect(updated.enableMiniTrailers, isFalse);
      expect(updated.enableHqVideos, isFalse);
      expect(updated.enableOnlineStream, isTrue);
      expect(updated.defaultViewMode, equals(initial.defaultViewMode));
    });

    test('6. GallerySettingsRepository persists and reloads video playback priority settings', () async {
      final initial = await repo.loadSettings();
      expect(initial.videoPlaybackPriority, equals([
        VideoSourceType.miniTrailer,
        VideoSourceType.hqVideo,
        VideoSourceType.onlineStream,
      ]));
      expect(initial.enableOnlineStream, isFalse);

      final custom = initial.copyWith(
        videoPlaybackPriority: [
          VideoSourceType.hqVideo,
          VideoSourceType.onlineStream,
          VideoSourceType.miniTrailer,
        ],
        enableOnlineStream: true,
        enableMiniTrailers: false,
      );

      await repo.saveSettings(custom);
      final reloaded = await repo.loadSettings();

      expect(reloaded.videoPlaybackPriority, equals([
        VideoSourceType.hqVideo,
        VideoSourceType.onlineStream,
        VideoSourceType.miniTrailer,
      ]));
      expect(reloaded.enableOnlineStream, isTrue);
      expect(reloaded.enableMiniTrailers, isFalse);
      expect(reloaded.enableHqVideos, isTrue);
    });
  });

  group('GallerySettingsScreen Video Playback Priority UI Tests', () {
    testWidgets('1. Renders Video Playback & Fallback Priority section and all three source tiles', (tester) async {
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

      expect(find.text('Video Playback & Fallback Priority'), findsOneWidget);
      expect(find.text('Drag to adjust playback preference. Top-most available source plays first.'), findsOneWidget);

      expect(find.text('MiniTrailer (Microtrailer)'), findsOneWidget);
      expect(find.text('6-second looping microtrailer (cached offline)'), findsOneWidget);

      expect(find.text('HQ Video (Full Trailer)'), findsOneWidget);
      expect(find.text('High-definition trailer from local cache / Drive'), findsOneWidget);

      expect(find.text('Online Stream (Steam CDN)'), findsOneWidget);
      expect(find.text('Stream directly from Steam over network (uses data)'), findsOneWidget);

      final miniSwitch = tester.widget<Switch>(find.byKey(const Key('switch_miniTrailer')));
      expect(miniSwitch.value, isTrue);

      final hqSwitch = tester.widget<Switch>(find.byKey(const Key('switch_hqVideo')));
      expect(hqSwitch.value, isTrue);

      final onlineSwitch = tester.widget<Switch>(find.byKey(const Key('switch_onlineStream')));
      expect(onlineSwitch.value, isFalse);
    });

    testWidgets('2. Toggling switch updates settings repository', (tester) async {
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

      final onlineSwitch = tester.widget<Switch>(find.byKey(const Key('switch_onlineStream')));
      await tester.runAsync(() async {
        onlineSwitch.onChanged!(true);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await repo.loadSettings();
      });
      expect(saved.enableOnlineStream, isTrue);
    });

    testWidgets('3. Reordering video priority list persists new order to settings', (tester) async {
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

      final reorderableFinder = find.byType(ReorderableListView);
      expect(reorderableFinder, findsOneWidget);
      final reorderable = tester.widget<ReorderableListView>(reorderableFinder);

      await tester.runAsync(() async {
        reorderable.onReorder(2, 0);
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      late GallerySettings saved;
      await tester.runAsync(() async {
        saved = await repo.loadSettings();
      });
      expect(saved.videoPlaybackPriority, equals([
        VideoSourceType.onlineStream,
        VideoSourceType.miniTrailer,
        VideoSourceType.hqVideo,
      ]));
    });
  });

  group('MicrotrailerPlayer Video Priority & Fallback Engine Tests', () {
    testWidgets('1. MiniTrailer plays by default when enabled and available', (tester) async {
      FakeVideoPlayerController? createdController;
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) {
        final c = FakeVideoPlayerController(uri);
        createdController = c;
        return c;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_preview',
              microtrailerDriveFileId: 'drive_preview_id',
              trailerDriveFileId: 'drive_full_id',
              trailerWebUrl: 'https://example.com/stream.mp4',
              gallerySettings: GallerySettings(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(createdController, isNotNull);
      expect(createdController!.initializeCalled, isTrue);
      expect(createdController!.playCalled, isTrue);
      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
    });

    testWidgets('2. Falls back to HQ Video when MiniTrailer is disabled', (tester) async {
      FakeVideoPlayerController? createdController;
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) {
        final c = FakeVideoPlayerController(uri);
        createdController = c;
        return c;
      };

      const settings = GallerySettings(
        enableMiniTrailers: false,
        enableHqVideos: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_hq_fallback',
              microtrailerDriveFileId: 'drive_preview_id',
              trailerDriveFileId: 'drive_full_id',
              gallerySettings: settings,
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsOneWidget);
      expect(createdController, isNull);

      await tester.tap(find.text('Watch Trailer'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(createdController, isNotNull);
      expect(createdController!.initializeCalled, isTrue);
      expect(createdController!.playCalled, isTrue);
    });

    testWidgets('3. Respects reordered priority: HQ Video prioritized over MiniTrailer', (tester) async {
      FakeVideoPlayerController? createdController;
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) {
        final c = FakeVideoPlayerController(uri);
        createdController = c;
        return c;
      };

      const settings = GallerySettings(
        videoPlaybackPriority: [
          VideoSourceType.hqVideo,
          VideoSourceType.miniTrailer,
          VideoSourceType.onlineStream,
        ],
        enableMiniTrailers: true,
        enableHqVideos: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_prio_hq',
              microtrailerDriveFileId: 'drive_preview_id',
              trailerDriveFileId: 'drive_full_id',
              gallerySettings: settings,
              autoStreamTrailersInHero: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(createdController, isNotNull);
      expect(createdController!.initializeCalled, isTrue);
      expect(createdController!.playCalled, isTrue);
    });

    testWidgets('4. Does NOT play Online Stream when enableOnlineStream is false (default)', (tester) async {
      FakeVideoPlayerController? createdController;
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) {
        final c = FakeVideoPlayerController(uri);
        createdController = c;
        return c;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_only_stream_disabled',
              trailerWebUrl: 'https://video.akamai.steamstatic.com/store_trailers/movie.mp4',
              gallerySettings: GallerySettings(enableOnlineStream: false),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsNothing);
      expect(createdController, isNull);
    });

    testWidgets('5. Plays Online Stream when enabled and other sources unavailable', (tester) async {
      FakeVideoPlayerController? createdController;
      MicrotrailerPlayer.enableInTests = true;
      MicrotrailerPlayer.testControllerFactory = (uri, headers) {
        final c = FakeVideoPlayerController(uri);
        createdController = c;
        return c;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MicrotrailerPlayer(
              gameId: 'game_stream_enabled',
              trailerWebUrl: 'https://video.akamai.steamstatic.com/store_trailers/movie.mp4',
              gallerySettings: GallerySettings(enableOnlineStream: true),
              autoStreamTrailersInHero: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('hero_watch_trailer_pill')), findsOneWidget);

      await tester.tap(find.text('Watch Trailer'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(createdController, isNotNull);
      expect(createdController!.initializeCalled, isTrue);
      expect(createdController!.lastUri.toString(), equals('https://video.akamai.steamstatic.com/store_trailers/movie.mp4'));
    });
  });

  group('GameDetailScreen Watch Full Trailer Visibility & Fallback Tests', () {
    testWidgets('1. Renders Watch Full Trailer button when HQ Video is available and enabled', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const game = UnifiedGamePayload(
        id: 'game_hq_ready',
        gameId: 'steam_100',
        pluginId: 'steam_plugin',
        name: 'Action Game',
        sortingName: 'Action Game',
        playtimeSeconds: 3600,
        media: MediaPayload(
          trailerDriveFileId: 'drive_hq_trailer_id',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: GameDetailScreen(game: game),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byKey(const Key('watch_trailer_button')), findsOneWidget);
      expect(find.text('Watch Full Trailer'), findsOneWidget);
    });

    testWidgets('2. Does not render Watch Full Trailer button when HQ Video is disabled in settings', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await repo.saveSettings(const GallerySettings(enableHqVideos: false));
      });

      const game = UnifiedGamePayload(
        id: 'game_hq_disabled',
        gameId: 'steam_101',
        pluginId: 'steam_plugin',
        name: 'Action Game 2',
        sortingName: 'Action Game 2',
        playtimeSeconds: 3600,
        media: MediaPayload(
          trailerDriveFileId: 'drive_hq_trailer_id',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: GameDetailScreen(game: game),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byKey(const Key('watch_trailer_button')), findsNothing);
    });

    testWidgets('3. Does not render Watch Full Trailer button when only trailerWebUrl is present and enableOnlineStream is false (default)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const game = UnifiedGamePayload(
        id: 'game_web_stream_default',
        gameId: 'steam_102',
        pluginId: 'steam_plugin',
        name: 'Online Game',
        sortingName: 'Online Game',
        playtimeSeconds: 3600,
        media: MediaPayload(
          trailerWebUrl: 'https://video.akamai.steamstatic.com/store_trailers/movie.mp4',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: GameDetailScreen(game: game),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byKey(const Key('watch_trailer_button')), findsNothing);
    });

    testWidgets('4. Renders Watch Full Trailer button when trailerWebUrl is present and enableOnlineStream is true', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await repo.saveSettings(const GallerySettings(enableOnlineStream: true));
      });

      const game = UnifiedGamePayload(
        id: 'game_web_stream_enabled',
        gameId: 'steam_103',
        pluginId: 'steam_plugin',
        name: 'Online Game 2',
        sortingName: 'Online Game 2',
        playtimeSeconds: 3600,
        media: MediaPayload(
          trailerWebUrl: 'https://video.akamai.steamstatic.com/store_trailers/movie.mp4',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: GameDetailScreen(game: game),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byKey(const Key('watch_trailer_button')), findsOneWidget);
    });
  });
}
