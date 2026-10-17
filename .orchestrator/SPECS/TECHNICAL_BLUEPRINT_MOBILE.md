# Technical Blueprint: Flutter Mobile Companion App (`playnite-mobile-companion`)

> **Specification Version:** 1.0.0  
> **Author:** Architect-Agent (Phase 2: Lead Systems Architect)  
> **Target Framework:** Flutter 3.x / Dart 3.x (Android & iOS)  
> **Target Project Name:** `playnite-mobile-companion`  
> **Audience:** Master Orchestrator, Spec-Verifier-Agent, Mobile-Lead-Agent (Phase 4)  
> **Status:** APPROVED FOR IMPLEMENTATION  

---

## 1. Executive Summary & Design Principles

The `playnite-mobile-companion` is a high-performance, offline-first mobile application designed to browse, filter, search, and inspect the user's desktop Playnite library, media assets, and addon statistics on iOS and Android devices.

### 1.1 Core Architecture Principles
1. **Offline-First Reactive Database (Drift / SQLite):** All game metadata, taxonomies, and addon statistics are stored locally in SQLite using **Drift**. UI queries run reactively with 60/120fps smoothness, zero network latency, and instant full-text search (FTS5).
2. **Strict Incremental Pull Protocol:** The mobile companion downloads only modified `games/{game_id}.json` files identified by diffing the remote `sync_index.json` against local hashes. A 1-game update downloads $< 15\text{ KB}$.
3. **Dynamic Addon Widget Registry (`AddonSectionRegistry`):** Satisfying the critical requirement for resilient addon addition and removal, the UI dynamically renders addon sections based on available payload keys. If an addon is removed or disabled on desktop, its mobile tab or card simply vanishes without errors; if a new unknown addon arrives, the app gracefully ignores it or renders a safe fallback inspector.
4. **Tiered Asynchronous Media Caching:** Covers and logos stream/cache on-demand; microtrailers prefetch or stream over Wi-Fi; full trailers stream strictly on demand.
5. **Read-Only Client Security:** The mobile app never writes to or modifies Google Drive, guaranteeing zero split-brain data conflicts.

---

## 2. System Architecture & Component Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FLUTTER MOBILE COMPANION APP                         │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │               Presentation Layer (Flutter 3.x)                 │   │
│   │  ├── LibraryScreen (Grid / List / Instant FTS5 Search)         │   │
│   │  ├── FilterDrawer (Platforms, Genres, Completion, Tags)        │   │
│   │  ├── GameDetailScreen (Hero Header, Video Loop, Addon Tabs)    │   │
│   │  │    └── AddonSectionRegistry (Dynamic Decoupled UI Cards)    │   │
│   │  └── StatsDashboardScreen (Playtime, Charts, Achievements)     │   │
│   └───────────────────────────────┬────────────────────────────────┘   │
│                                   │ State / Events                     │
│   ┌───────────────────────────────▼────────────────────────────────┐   │
│   │             State Management Layer (Riverpod 2.x)              │   │
│   │  ├── LibraryNotifier & FilterStateProvider                     │   │
│   │  ├── SyncController (SyncStatus, ProgressNotifier)             │   │
│   │  └── MediaDownloadNotifier                                     │   │
│   └───────────────┬───────────────────────────────┬────────────────┘   │
│                   │ Queries                       │ Sync Triggers      │
│   ┌───────────────▼──────────────┐  ┌─────────────▼────────────────┐   │
│   │      Data / Storage Layer    │  │       Delta Sync Engine      │   │
│   │   (Drift / SQLite Database)  │  │     (DeltaPullManager)       │   │
│   │  ├── GamesTable              │  │  ├── IndexDiffEngine         │   │
│   │  ├── AddonTables             │  │  ├── BatchDownloadWorker     │   │
│   │  ├── FullTextSearch (FTS5)   │  │  └── DriveOAuth2Client       │   │
│   │  └── SyncMetaTable           │  │                              │   │
│   └───────────────▲──────────────┘  └─────────────┬────────────────┘   │
│                   │ Ingestion Transaction         │                    │
│   ┌───────────────┴───────────────────────────────▼────────────────┐   │
│   │           Tiered Media Cache Layer (CachedNetworkImage)        │   │
│   │  ├── Tier 1: Covers & Logos (LRU Disk Cache, WebP / PNG)       │   │
│   │  ├── Tier 2: Microtrailers (VideoPlayerController Cache)       │   │
│   │  └── Tier 3: Full Trailers (HTTP Range Streaming Only)         │   │
│   └───────────────────────────────┬────────────────────────────────┘   │
└───────────────────────────────────┼────────────────────────────────────┘
                                    │ HTTPS REST (Scoped drive.file)
┌───────────────────────────────────▼────────────────────────────────────┐
│                    GOOGLE DRIVE CLOUD STORAGE                          │
│                                                                        │
│   PlayniteSync/                                                        │
│   ├── sync_index.json                                                  │
│   ├── manifest.json                                                    │
│   ├── games/{game_id}.json                                             │
│   └── media/{covers|backgrounds|logos|microtrailers}                   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Project Directory Layout (Feature-First Clean Architecture)

```
playnite-mobile-companion/
├── pubspec.yaml
├── lib/
│   ├── main.dart                            # Application entry point & Riverpod Scope
│   │
│   ├── core/                                # Shared infrastructure & utilities
│   │   ├── config/                          # App theme, constants, typography
│   │   ├── database/                        # Drift database definitions & DAOs
│   │   │   ├── app_database.dart            # Drift database class & migration runner
│   │   │   ├── tables/
│   │   │   │   ├── games_table.dart         # Core games schema
│   │   │   │   ├── taxonomy_tables.dart     # Platforms, Genres, Sources, Tags
│   │   │   │   ├── addon_tables.dart        # Achievements, Sessions, HLTB, DLC
│   │   │   │   └── sync_meta_table.dart     # Local hash storage for delta diffs
│   │   │   └── daos/
│   │   │       ├── game_dao.dart            # FTS5 search, filtering, and sorting
│   │   │       ├── taxonomy_dao.dart        # Dictionaries & lookup tables
│   │   │       └── stats_dao.dart           # Aggregated playtime & completion metrics
│   │   ├── network/
│   │   │   ├── drive_auth_client.dart       # GoogleSignIn & OAuth2 authenticated client
│   │   │   └── drive_api_service.dart       # Google Drive v3 REST wrapper
│   │   └── utils/
│   │       ├── duration_formatter.dart      # Converts strict seconds -> "26h 15m"
│   │       └── media_url_resolver.dart      # Maps Drive fileId -> direct media stream
│   │
│   └── features/
│       ├── sync/                            # Delta synchronization engine
│       │   ├── data/
│       │   │   ├── delta_pull_manager.dart  # Index comparison & delta download orchestrator
│       │   │   ├── sync_index_parser.dart   # Stream parser for sync_index.json
│       │   │   └── batch_ingestion_service.dart # Atomic SQLite bulk upsert
│       │   ├── domain/
│       │   │   └── sync_models.dart         # PullDiff, SyncReport, SyncState
│       │   └── presentation/
│       │       ├── sync_controller.dart     # Riverpod StateNotifier for sync progress
│       │       └── widgets/
│       │           ├── sync_progress_banner.dart
│       │           └── sync_settings_tile.dart
│       │
│       ├── library/                         # Game library browsing & filtering
│       │   ├── domain/
│       │   │   ├── game_filter_criteria.dart # Active filter selections
│       │   │   └── sort_options.dart        # Title, Playtime, Last Played, Score
│       │   ├── presentation/
│       │   │   ├── library_screen.dart      # Main screen with Grid/List/Details toggle
│       │   │   ├── library_controller.dart  # Riverpod provider for filtered games
│       │   │   └── widgets/
│       │   │       ├── game_card_grid.dart  # High-framerate grid item with WebP cover
│       │   │       ├── game_list_tile.dart  # Compact row item with badges
│       │   │       ├── library_search_bar.dart # Instant FTS5 input
│       │   │       └── filter_bottom_sheet.dart # Multi-select platforms, genres, etc.
│       │
│       ├── game_detail/                     # Detail view with dynamic addon registry
│       │   ├── presentation/
│       │   │   ├── game_detail_screen.dart  # Hero banner & dynamic tabs
│       │   │   ├── widgets/
│       │   │   │   ├── hero_media_header.dart # Microtrailer auto-play + Title Logo
│       │   │   │   ├── play_time_card.dart    # Total playtime & last played
│       │   │   │   └── metadata_chips_row.dart# Platforms, genres, scores
│       │   │   └── addon_registry/          # Dynamic decoupled addon UI system
│       │   │       ├── addon_section_registry.dart # Registry binding keys to widgets
│       │   │       ├── i_addon_widget.dart      # Abstract widget interface
│       │   │       └── sections/
│       │   │           ├── achievements_section.dart # SuccessStory visual achievements
│       │   │           ├── hltb_section.dart         # HowLongToBeat visual time bars
│       │   │           ├── activity_section.dart     # GameActivity session history & graph
│       │   │           ├── dlc_section.dart          # CheckDlc item catalog & owned chips
│       │   │           ├── requirements_section.dart # SystemChecker hardware specs
│       │   │           └── fallback_addon_section.dart # Unknown addon inspector
│       │
│       └── stats/                           # Global library statistics dashboard
│           ├── presentation/
│           │   ├── stats_dashboard_screen.dart
│           │   └── widgets/
│           │       ├── playtime_summary_card.dart
│           │       ├── completion_pie_chart.dart
│           │       ├── platform_breakdown_bar.dart
│           │       └── most_played_leaderboard.dart
```

---

## 4. Local Database Architecture (Drift / SQLite)

### 4.1 Schema Definitions (`core/database/tables/`)

```dart
import 'package:drift/drift.dart';

// Core Game Table
@DataClassName('GameEntry')
class GamesTable extends Table {
  TextColumn get id => text()(); // Playnite UUID PK
  TextColumn get gameId => text()(); // Store AppID (Steam, Epic, etc.)
  TextColumn get pluginId => text()();
  TextColumn get name => text()();
  TextColumn get sortingName => text()();
  TextColumn get description => text().nullable()();
  TextColumn get notes => text().nullable()();
  Int64Column get playtimeSeconds => int64().withDefault(const Constant(0))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedUtc => dateTime().nullable()();
  DateTimeColumn get modifiedUtc => dateTime().nullable()();
  DateTimeColumn get lastActivityUtc => dateTime().nullable()();
  TextColumn get releaseDate => text().nullable()();
  BoolColumn get isInstalled => boolean().withDefault(const Constant(false))();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get userScore => integer().nullable()();
  IntColumn get criticScore => integer().nullable()();
  IntColumn get communityScore => integer().nullable()();
  
  // Primary relational Foreign Keys
  TextColumn get sourceId => text().nullable()();
  TextColumn get completionStatusId => text().nullable()();

  // Media references (Drive File IDs and hashes for direct streaming)
  TextColumn get coverDriveFileId => text().nullable()();
  TextColumn get coverSha256 => text().nullable()();
  TextColumn get backgroundDriveFileId => text().nullable()();
  TextColumn get logoDriveFileId => text().nullable()();
  TextColumn get microtrailerDriveFileId => text().nullable()();
  TextColumn get trailerDriveFileId => text().nullable()();

  // Raw Addons JSON Container (Preserves future & custom addons without migration)
  TextColumn get addonsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

// Full-Text Search (FTS5) Virtual Table for Instant Search
class GamesFts extends Table {
  TextColumn get name => text()();
  TextColumn get sortingName => text()();
  TextColumn get description => text()();
  TextColumn get notes => text()();
}

// Local Sync Metadata for Delta Hashing
class SyncMetaTable extends Table {
  TextColumn get relativePath => text()(); // e.g. "games/{id}.json"
  TextColumn get sha256 => text()();
  Int64Column get sizeBytes => int64()();
  DateTimeColumn get lastSyncedUtc => dateTime()();
  TextColumn get driveFileId => text()();

  @override
  Set<Column> get primaryKey => {relativePath};
}
```

### 4.2 Normalized Addon Child Tables
While the raw `addonsJson` column in `GamesTable` provides zero-cost extensibility for future plugins, high-cardinality known addons are unpacked into relational tables for instant queries:

1. **`AchievementsTable`:** `gameId`, `apiName`, `name`, `description`, `urlUnlocked`, `urlLocked`, `dateUnlockedUtc`, `percent`, `gamerScore`, `isHidden`.
2. **`PlaySessionsTable`:** `gameId`, `dateSessionUtc`, `elapsedSeconds`, `actionName`.
3. **`HltbDataTable`:** `gameId`, `mainStorySeconds`, `mainExtraSeconds`, `completionistSeconds`.
4. **`DlcItemsTable`:** `gameId`, `dlcId`, `name`, `isOwned`, `price`, `imageUrl`.

---

## 5. Delta Sync Engine (`DeltaPullManager`)

The `DeltaPullManager` implements the pull protocol specified in `DELTA_SYNC_SPEC.md`.

```dart
class DeltaPullManager {
  final DriveApiService driveService;
  final AppDatabase database;
  final Ref ref;

  DeltaPullManager(this.driveService, this.database, this.ref);

  Future<SyncReport> executeDeltaPull({ProgressCallback? onProgress}) async {
    // 1. Fetch remote sync_index.json
    final remoteIndex = await driveService.fetchSyncIndex();
    
    // 2. Query local sync metadata
    final localEntries = await database.syncMetaDao.getAllEntries();
    final localMap = {for (var e in localEntries) e.relativePath: e};

    // 3. Compute Delta Diff
    final toDownload = <IndexEntry>[];
    for (final entry in remoteIndex.entries.values) {
      if (entry.category != 'game_metadata' && entry.category != 'manifest') {
        continue; // Media is handled asynchronously by MediaCacheManager
      }

      final local = localMap[entry.relativePath];
      if (local == null || local.sha256 != entry.sha256) {
        toDownload.add(entry);
      }
    }

    final remotePaths = remoteIndex.entries.keys.toSet();
    final toDelete = localEntries
        .where((e) => !remotePaths.contains(e.relativePath) && e.relativePath.startsWith('games/'))
        .map((e) => e.relativePath)
        .toList();

    if (toDownload.isEmpty && toDelete.isEmpty) {
      return SyncReport.noOp(); // Fast path: 0 downloads needed!
    }

    // 4. Download Game Payloads in Parallel (Concurrency: 4)
    final downloadedPayloads = <UnifiedGamePayload>[];
    final queue = Stream.fromIterable(toDownload);
    
    await for (final batch in queue.buffer(4)) {
      final futures = batch.map((item) async {
        final jsonString = await driveService.downloadFileText(item.driveFileId);
        return UnifiedGamePayload.fromJson(jsonDecode(jsonString));
      });
      final results = await Future.wait(futures);
      downloadedPayloads.addAll(results);
      onProgress?.call(downloadedPayloads.length, toDownload.length);
    }

    // 5. Atomic Batch Ingestion inside SQLite Transaction
    await database.transaction(() async {
      // Ingest Games & Child Addon Tables
      await database.gameDao.batchUpsertGames(downloadedPayloads);

      // Cascade Delete removed games
      if (toDelete.isNotEmpty) {
        final deletedIds = toDelete.map((p) => p.replaceAll('games/', '').replaceAll('.json', ''));
        await database.gameDao.batchDeleteGames(deletedIds);
      }

      // Update Local Sync Meta
      await database.syncMetaDao.batchUpsertMeta(toDownload.map((e) => SyncMetaCompanion(
        relativePath: Value(e.relativePath),
        sha256: Value(e.sha256),
        sizeBytes: Value(BigInt.from(e.sizeBytes)),
        lastSyncedUtc: Value(DateTime.now().toUtc()),
        driveFileId: Value(e.driveFileId),
      )));
    });

    return SyncReport.success(
      downloadedCount: downloadedPayloads.length,
      deletedCount: toDelete.length,
    );
  }
}
```

---

## 6. Dynamic Addon Section Registry (`AddonSectionRegistry`)

### 6.1 Architectural Guarantee
To satisfy the user requirement that **adding or removing addons must never break the system**, the mobile UI employs a polymorphic registry pattern. The Game Detail View queries the registry dynamically:

```dart
abstract class IAddonSectionWidget {
  String get addonKey;
  int get displayOrder;
  Widget buildSection(BuildContext context, GameDetailData gameData);
}

class AddonSectionRegistry {
  static final Map<String, IAddonSectionWidget> _registry = {};

  static void register(IAddonSectionWidget widget) {
    _registry[widget.addonKey] = widget;
  }

  static List<Widget> buildAvailableSections(BuildContext context, GameDetailData gameData) {
    final availableWidgets = <Widget>[];
    
    // Sort registered sections by predefined display order
    final sortedSections = _registry.values.toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    for (final section in sortedSections) {
      // Check if this game contains valid data for this addon
      if (gameData.hasAddonData(section.addonKey)) {
        try {
          availableWidgets.add(section.buildSection(context, gameData));
        } catch (e, stack) {
          debugPrint('Error rendering addon section ${section.addonKey}: $e\n$stack');
          // Graceful fallback: do NOT crash screen, omit faulty section
        }
      }
    }

    // Handle unknown / custom future addons gracefully
    final unknownKeys = gameData.addons.keys
        .where((key) => !_registry.containsKey(key))
        .toList();

    for (final unknownKey in unknownKeys) {
      availableWidgets.add(FallbackAddonSection(
        addonKey: unknownKey,
        data: gameData.addons[unknownKey],
      ));
    }

    return availableWidgets;
  }
}
```

### 6.2 Concrete Addon Widgets
1. **`AchievementsSection` (`success_story`):**
   - Displays unlock progress bar ($42 / 50$ unlocked, $84\%$).
   - Filter tabs: All, Unlocked, Locked, Secret.
   - List tiles with icon, title, description, GamerScore, and unlock timestamp.
2. **`HltbSection` (`how_long_to_beat`):**
   - Converts strict seconds to human-readable strings via `DurationFormatter`:
     `93612s` $\to$ `"26 Hours"`
   - Interactive bar chart showing Main Story vs. Main + Extra vs. Completionist.
3. **`ActivitySection` (`game_activity`):**
   - Recent play session tiles with date and session duration.
   - Cumulative monthly playtime graph.
4. **`DlcSection` (`check_dlc`):**
   - Card list of DLCs with title, price, and green "Owned" chip or store link.
5. **`RequirementsSection` (`system_checker`):**
   - Side-by-side Minimum vs. Recommended spec cards (OS, CPU, GPU, RAM, Storage).

---

## 7. Media Synchronization & Video Auto-Play

### 7.1 Tiered Media Architecture
- **Tier 1 (Covers & Logos):** Displayed via `CachedNetworkImage` with custom Google Drive headers (`Authorization: Bearer <token>`). Uses thumbnail sizing to minimize memory pressure.
- **Tier 2 (Microtrailers):** Auto-plays seamlessly on the Game Detail screen:
  - Uses `video_player` controller in a looping, muted configuration.
  - Video resolution is SD $630\times354$ at 60fps, consuming $< 2\text{ MB}$.
  - Pre-cached locally when user views the screen.
- **Tier 3 (Trailers):** Full cinematic trailers are streamed on-demand when the user clicks the "Watch Trailer" FAB button.

### 7.2 Microtrailer Auto-Play Widget

```dart
class MicrotrailerPlayer extends StatefulWidget {
  final String? driveFileId;
  final String? backgroundFileId;

  const MicrotrailerPlayer({Key? key, this.driveFileId, this.backgroundFileId}) : super(key: key);

  @override
  State<MicrotrailerPlayer> createState() => _MicrotrailerPlayerState();
}

class _MicrotrailerPlayerState extends State<MicrotrailerPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.driveFileId != null) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final streamUrl = MediaUrlResolver.getDriveMediaStreamUrl(widget.driveFileId!);
    final headers = await MediaUrlResolver.getAuthHeaders();

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(streamUrl),
      httpHeaders: headers,
    );

    try {
      await _controller!.initialize();
      _controller!.setLooping(true);
      _controller!.setVolume(0.0); // Muted preview loop
      _controller!.play();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Microtrailer playback error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialized && _controller != null) {
      return AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      );
    }

    // Fallback to static fanart background while loading or if video absent
    return StaticBackgroundFanart(driveFileId: widget.backgroundFileId);
  }
}
```

---

## 8. Screen Specifications & UI Flow

```
┌────────────────────────┐     ┌────────────────────────┐     ┌────────────────────────┐
│     LIBRARY VIEW       │     │   GAME DETAIL VIEW     │     │    STATS DASHBOARD     │
├────────────────────────┤     ├────────────────────────┤     ├────────────────────────┤
│ [Search games...     ] │     │ [ < Back ]   [Share]   │     │ Total Library Playtime │
│ [Grid] [List] [Filter] │     │ ┌────────────────────┐ │     │ 5,125 Hours (213 Days) │
├────────────────────────┤     │ │ Microtrailer Loop  │ │     ├────────────────────────┤
│ ┌─────┐ ┌─────┐ ┌─────┐│     │ │   & Transparent    │ │     │ Completion Status      │
│ │Cover│ │Cover│ │Cover││     │ │      Logo.png      │ │     │  Completed: 24%        │
│ │ #1  │ │ #2  │ │ #3  ││     │ └────────────────────┘ │     │  Beaten:    18%        │
│ └─────┘ └─────┘ └─────┘│────>│ Encased: Sci-Fi RPG    │     │  Playing:   8%         │
│ ┌─────┐ ┌─────┐ ┌─────┐│Tap  │ ★ 86%  |  PC (Windows) │     │  Not Played:50%        │
│ │Cover│ │Cover│ │Cover││     ├────────────────────────┤     ├────────────────────────┤
│ │ #4  │ │ #5  │ │ #6  ││     │ [Achieve] [HLTB] [DLC] │     │ Top 5 Most Played      │
│ └─────┘ └─────┘ └─────┘│     │  Main Story: 26.0h     │     │ 1. Cyberpunk (210h)    │
│                        │     │  Extra:      39.8h     │     │ 2. The Witcher 3 (185h)│
│                        │     │  Completion: 67.5h     │     │ 3. Elden Ring (142h)   │
└────────────────────────┘     └────────────────────────┘     └────────────────────────┘
```

---

## 9. Verification & QA Gates for Phase 4 Implementation
1. **Delta Pull Verification:** Pulling updates when only 2 of 1,429 games have modified timestamps must transfer $< 30\text{ KB}$ and ingest in $< 500\text{ ms}$.
2. **Addon Extensibility Test:** Injecting a mock `custom_future_addon` key into a game payload must parse without errors and render safely via `FallbackAddonSection`.
3. **Addon Removal Test:** Removing `how_long_to_beat` from a game payload must instantly omit the HLTB tab on the detail screen with zero UI rendering errors.
4. **Offline Resilience Test:** Launching the app in Airplane mode must immediately render the full cached library from Drift with 120fps scrolling.
