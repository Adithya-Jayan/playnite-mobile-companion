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
1. **Offline-First Reactive Database (`sqflite` / SQLite - ADR 0001):** As ratified in [`docs/adr/0001-sqflite-raw-sql-store.md`](file:///C:/Users/adith/Documents/Code/Playnite_Addon/docs/adr/0001-sqflite-raw-sql-store.md), all game metadata, taxonomies, and addon statistics are stored locally in SQLite using `sqflite` with raw SQL queries and denormalized JSON columns (`addons_json`, `platforms_json`, `links_json`, `other_copies_json`). UI queries run reactively with 60/120fps smoothness, zero network latency, and instant full-text search (FTS5/FTS4).
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
│   │  ├── LibraryScreen (Grid / List / Alphabet Scrubber / FTS5)    │   │
│   │  │    └── Actions: 🎲 Surprise Me (Random Picker), Sort (Random)│   │
│   │  ├── FilterDrawer (Platforms, Genres, Completion, Tags)        │   │
│   │  ├── GameDetailScreen (Hero Header, Video Loop, Addon Tabs)    │   │
│   │  │    └── AddonSectionRegistry (Dynamic Decoupled UI Cards)    │   │
│   │  ├── GallerySettingsScreen (Scrub-Bar Toggle, Auto-Fade)       │   │
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
│   │ (sqflite / SQLite - ADR 0001)│  │     (DeltaPullManager)       │   │
│   │  ├── games (with JSON cols)  │  │  ├── IndexDiffEngine         │   │
│   │  ├── Addon child tables      │  │  ├── BatchDownloadWorker     │   │
│   │  ├── games_fts (FTS5 / FTS4) │  │  └── DriveOAuth2Client       │   │
│   │  └── sync_entries / meta     │  │                              │   │
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
│   │   ├── database/                        # SQLite database & raw SQL DAOs (ADR 0001)
│   │   │   ├── app_database.dart            # sqflite connection, schema creation & column validation
│   │   │   └── daos/
│   │   │       ├── game_dao.dart            # Raw SQL queries, FTS5 search, filtering & sorting (Random, Playtime)
│   │   │       ├── taxonomy_dao.dart        # Taxonomy dictionaries & distinct column lookups
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
│       │   │   └── sort_options.dart        # Title, Playtime, Last Played, Score, Random (RANDOM())
│       │   ├── presentation/
│       │   │   ├── library_screen.dart      # Main screen with Alphabet Scrubber & Random Surprise Me
│       │   │   ├── library_controller.dart  # Riverpod provider for filtered games
│       │   │   └── widgets/
│       │   │       ├── game_card_grid.dart  # High-framerate grid item with WebP cover
│       │   │       ├── game_list_tile.dart  # Compact row item with badges
│       │   │       ├── library_search_bar.dart # Instant FTS5 input
│       │   │       └── filter_bottom_sheet.dart # Multi-select platforms, genres, etc.
│       │
│       ├── settings/                        # User gallery & player preferences
│       │   ├── data/
│       │   │   └── gallery_settings_repository.dart # SQLite manifest_meta store for video scrub bar (ADR 0001)
│       │   └── presentation/
│       │       └── gallery_settings_screen.dart # Gallery settings UI (showVideoScrubBar toggle)
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

## 4. Local Database Architecture (sqflite / SQLite - ADR 0001)

### 4.1 Decision & Rationale (Ratifying ADR 0001)
As ratified in [`docs/adr/0001-sqflite-raw-sql-store.md`](file:///C:/Users/adith/Documents/Code/Playnite_Addon/docs/adr/0001-sqflite-raw-sql-store.md), `playnite-mobile-companion` adopts **`sqflite` with raw SQL queries and denormalized JSON columns** (`addons_json`, `platforms_json`, `links_json`, `other_copies_json`) instead of Drift ORM:
- **Resilience to Addon Schema Drift:** Third-party Playnite plugins (SuccessStory, HowLongToBeat, GameActivity, DuplicateHider) frequently evolve their payload structures. Raw JSON storage guarantees zero SQLite table migration failures or deserialization crashes during app updates.
- **High-Throughput Bulk Ingestion:** Bulk delta ingestion writes raw SQLite transaction batches directly, achieving $< 500\text{ ms}$ ingestion times for thousands of titles without ORM mapping overhead.
- **Android Cursor Window Protection:** Mobile SQLite enforces a strict 2 MB `CursorWindow` limit. `GameDao` selectively projects only essential summary columns during library grid/list queries, completely omitting large `addons_json` blobs until the user opens the `GameDetailScreen`.
- **Cross-Platform SQLite Engine:** Uses built-in Android/iOS SQLite engines, and `sqflite_common_ffi` for desktop testing, eliminating complex FFI compilation boundaries.

### 4.2 Schema Definitions (`lib/core/database/app_database.dart`)

```sql
-- 1. Core Games Table
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,
  game_id TEXT NOT NULL,
  plugin_id TEXT NOT NULL,
  name TEXT NOT NULL,
  sorting_name TEXT NOT NULL,
  description TEXT,
  notes TEXT,
  playtime_seconds INTEGER NOT NULL DEFAULT 0,
  play_count INTEGER NOT NULL DEFAULT 0,
  added_utc TEXT,
  modified_utc TEXT,
  last_activity_utc TEXT,
  recent_activity_utc TEXT,
  release_date TEXT,
  is_installed INTEGER NOT NULL DEFAULT 0,
  install_directory TEXT,
  install_size_bytes INTEGER,
  hidden INTEGER NOT NULL DEFAULT 0,
  is_duplicate INTEGER NOT NULL DEFAULT 0,
  duplicate_group_id TEXT,
  other_copies_json TEXT NOT NULL DEFAULT '[]',
  favorite INTEGER NOT NULL DEFAULT 0,
  user_score INTEGER,
  critic_score INTEGER,
  community_score INTEGER,
  version TEXT,
  source_id TEXT,
  source_name TEXT,
  completion_status_id TEXT,
  completion_status_name TEXT,
  cover_drive_file_id TEXT,
  cover_sha256 TEXT,
  background_drive_file_id TEXT,
  background_sha256 TEXT,
  icon_drive_file_id TEXT,
  icon_sha256 TEXT,
  logo_drive_file_id TEXT,
  microtrailer_drive_file_id TEXT,
  trailer_drive_file_id TEXT,
  trailer_web_url TEXT,
  platforms_json TEXT NOT NULL DEFAULT '[]',
  genres_json TEXT NOT NULL DEFAULT '[]',
  categories_json TEXT NOT NULL DEFAULT '[]',
  tags_json TEXT NOT NULL DEFAULT '[]',
  developers_json TEXT NOT NULL DEFAULT '[]',
  publishers_json TEXT NOT NULL DEFAULT '[]',
  features_json TEXT NOT NULL DEFAULT '[]',
  series_json TEXT NOT NULL DEFAULT '[]',
  links_json TEXT NOT NULL DEFAULT '[]',
  addons_json TEXT NOT NULL DEFAULT '{}'
);

-- Indexes for lightning-fast library sorting & filtering
CREATE INDEX IF NOT EXISTS idx_games_sorting_name ON games(sorting_name);
CREATE INDEX IF NOT EXISTS idx_games_playtime ON games(playtime_seconds DESC);
CREATE INDEX IF NOT EXISTS idx_games_last_activity ON games(last_activity_utc DESC);
CREATE INDEX IF NOT EXISTS idx_games_source ON games(source_name);
CREATE INDEX IF NOT EXISTS idx_games_completion ON games(completion_status_name);
CREATE INDEX IF NOT EXISTS idx_games_is_installed ON games(is_installed);
CREATE INDEX IF NOT EXISTS idx_games_favorite ON games(favorite);

-- 2. Full-Text Search (FTS5 / FTS4) Virtual Table
CREATE VIRTUAL TABLE IF NOT EXISTS games_fts USING fts5(
  name, sorting_name, description, notes, content='games', content_rowid='rowid'
);

-- 3. Sync Entries Table (Local representation of sync_index.json)
CREATE TABLE IF NOT EXISTS sync_entries (
  relative_path TEXT PRIMARY KEY,
  sha256 TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_utc TEXT NOT NULL,
  drive_file_id TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  category TEXT NOT NULL,
  game_id TEXT,
  last_synced_utc TEXT NOT NULL
);

-- 4. Manifest Meta Table (Library dictionaries & summary metrics)
CREATE TABLE IF NOT EXISTS manifest_meta (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_utc TEXT NOT NULL
);

-- 5. Normalized Addon Tables for Fast Relational Views
CREATE TABLE IF NOT EXISTS achievements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  api_name TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  url_unlocked TEXT,
  url_locked TEXT,
  date_unlocked_utc TEXT,
  percent REAL,
  gamerscore REAL,
  is_hidden INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS play_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  date_session_utc TEXT NOT NULL,
  elapsed_seconds INTEGER NOT NULL,
  action_name TEXT
);
CREATE TABLE IF NOT EXISTS hltb_data (
  game_id TEXT PRIMARY KEY,
  main_story_seconds INTEGER NOT NULL DEFAULT 0,
  main_extra_seconds INTEGER NOT NULL DEFAULT 0,
  completionist_seconds INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS dlc_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  dlc_id TEXT NOT NULL,
  name TEXT NOT NULL,
  is_owned INTEGER NOT NULL DEFAULT 0,
  price TEXT,
  image_url TEXT
);
```

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

    // 5. Atomic Batch Ingestion inside sqflite Transaction (ADR 0001)
    await database.db.transaction((txn) async {
      // Ingest Games & Normalized Child Addon Tables
      await database.gameDao.batchUpsertGames(downloadedPayloads, executor: txn);

      // Cascade Delete removed games
      if (toDelete.isNotEmpty) {
        final deletedIds = toDelete.map((p) => p.replaceAll('games/', '').replaceAll('.json', '')).toList();
        await database.gameDao.batchDeleteGames(deletedIds, executor: txn);
      }

      // Update Local Sync Meta
      for (final e in toDownload) {
        await txn.insert('sync_entries', {
          'relative_path': e.relativePath,
          'sha256': e.sha256,
          'size_bytes': e.sizeBytes,
          'modified_utc': e.modifiedUtc,
          'drive_file_id': e.driveFileId,
          'mime_type': e.mimeType,
          'category': e.category,
          'game_id': e.gameId,
          'last_synced_utc': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
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

### 7.3 Gallery Settings & Scrub-Bar Customization
The companion application provides fine-grained user control over video playback and gallery UI ergonomics via `GallerySettingsRepository`:
- **`showVideoScrubBar` Setting:** Persisted in SQLite `manifest_meta` (ADR 0001, default: `true`). When toggled off in `GallerySettingsScreen`, the `MicrotrailerPlayer` suppresses the bottom progress scrub bar and timestamps, presenting an uncluttered cinematic presentation while preserving touch auto-fade and decoupled audio mute/unmute controls.
- **Alphabetical Fast-Scroll Scrubber:** On the `LibraryScreen`, when sorting alphabetically by Title and viewing $\ge 10$ games, an interactive vertical alphabet rail (`_buildAlphabetScrubber`) appears along the right display edge. Users can drag or tap to instantly jump across the library with haptic feedback and a floating bubble HUD (`_scrubbingLetter`).

---

## 8. Screen Specifications & UI Flow

```
┌────────────────────────┐     ┌────────────────────────┐     ┌────────────────────────┐
│     LIBRARY VIEW       │     │   GAME DETAIL VIEW     │     │    STATS DASHBOARD     │
├────────────────────────┤     ├────────────────────────┤     ├────────────────────────┤
│ [Search games...     ] │     │ [ < Back ]   [Share]   │     │ Total Library Playtime │
│ [Grid] [List] [Filter] │     │ ┌────────────────────┐ │     │ 5,125 Hours (213 Days) │
│ [🎲 Random] [Sort: A-Z]│     │ │ Microtrailer Loop  │ │     ├────────────────────────┤
├────────────────────────┤     │ │   & Transparent    │ │     │ Completion Status      │
│ ┌─────┐ ┌─────┐ ┌─────┐│     │ │      Logo.png      │ │     │  Completed: 24%        │
│ │Cover│ │Cover│ │Cover││     │ └────────────────────┘ │     │  Beaten:    18%        │
│ │ #1  │ │ #2  │ │ #3  ││     │ Encased: Sci-Fi RPG    │     │  Playing:   8%         │
│ └─────┘ └─────┘ └─────┘│────>│ ★ 86%  |  PC (Windows) │     │  Not Played:50%        │
│ ┌─────┐ ┌─────┐ ┌─────┐│Tap  ├────────────────────────┤     ├────────────────────────┤
│ │Cover│ │Cover│ │Cover││     │ [Achieve] [HLTB] [DLC] │     │ Top 5 Most Played      │
│ │ #4  │ │ #5  │ │ #6  ││     │  Main Story: 26.0h     │     │ 1. Cyberpunk (210h)    │
│ └─────┘ └─────┘ └─────┘│     │  Extra:      39.8h     │     │ 2. The Witcher 3 (185h)│
│                        │     │  Completion: 67.5h     │     │ 3. Elden Ring (142h)   │
└────────────────────────┘     └────────────────────────┘     └────────────────────────┘

### 8.1 Random Sorting & "Surprise Me" Game Picker
To solve decision paralysis across large libraries (1,000+ titles):
1. **Random Sort Option (`SortOption.random`):** Injects SQL `ORDER BY RANDOM()` in `GameDao.getFilteredGames()`, shuffling the library display.
2. **"🎲 Surprise Me" Action Button:** Positioned directly in the `LibraryScreen` app bar, this action filters the eligible pool according to current active filter chips, randomly selects a title, and opens `GameDetailScreen` with an animated snackbar toast.
```

---

## 9. Verification & QA Gates for Phase 4 Implementation
1. **Delta Pull Verification:** Pulling updates when only 2 of 1,429 games have modified timestamps must transfer $< 30\text{ KB}$ and ingest in $< 500\text{ ms}$.
2. **Addon Extensibility Test:** Injecting a mock `custom_future_addon` key into a game payload must parse without errors and render safely via `FallbackAddonSection`.
3. **Addon Removal Test:** Removing `how_long_to_beat` from a game payload must instantly omit the HLTB tab on the detail screen with zero UI rendering errors.
4. **Offline Resilience Test:** Launching the app in Airplane mode must immediately render the full cached library from `sqflite` with 120fps scrolling.

---

## 10. Playnite Toolbox Auto-Updater Manifest (`installer.yaml`)

To provide automated desktop extension updates directly through Playnite's native Addon Manager without requiring manual `.pext` downloads or zip extractions, the desktop exporter exposes an `installer.yaml` manifest in the repository root:

```yaml
AddonId: "MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a"
Packages:
  - Version: 1.2.0
    RequiredApiVersion: 6.0.0
    ReleaseDate: 2026-10-19
    PackageUrl: https://github.com/Adithya-Jayan/playnite-mobile-companion/releases/download/v1.2.0/MobileDeltaSyncExporter.pext
    Changelog:
      - Added high-resolution custom app logo & mascot branding
      - Alphabet fast-scroll scrubber synchronization with haptic indexing
      - Video player streaming fixes for direct web and Google Drive trailers
      - Controls clean auto-fade by default on playback
      - Honored Gallery Settings scrub bar toggle with decoupled audio controls
      - Top app bar scroll tint fix (retains deep gray surface)
      - Added Random game sort and top bar random picker
      - Added expandable Tag filter and fixed Missing Cover utility filter
      - Added in-app GitHub repository link
```

### 10.1 Key Manifest Invariants
- **`AddonId`:** Must strictly match the GUID declared in `extension.yaml` (`MobileDeltaSyncExporter_d3b07384-d113-4c90-951b-10f88a91a92a`).
- **`RequiredApiVersion`:** Declares the minimum Playnite SDK API version (`6.0.0`) required for desktop compatibility.
- **`PackageUrl`:** Points to the downloadable `.pext` binary asset attached to the tagged GitHub Release.
- **`Playnite.Toolbox.exe` Compatibility:** When the user checks for addon updates in Playnite Desktop, Playnite queries this manifest, compares the installed version against `Packages[0].Version`, and downloads the update automatically.
