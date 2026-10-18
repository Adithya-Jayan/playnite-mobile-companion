# Phase 2 Revised Architecture Specification & Proactive Feature Design

> **Document Version:** 2.0.0  
> **Author:** Lead Systems Architect (Architect-Agent)  
> **Status:** APPROVED FOR IMPLEMENTATION  
> **Target Systems:** `playnite-exporter-plugin` (C# / .NET 6), `playnite-mobile-companion` (Flutter 3.x / Dart 3.x / SQLite / Drift)  
> **Inputs Audited:**  
> 1. `.orchestrator/AUDIT_REPORTS/DATA_PIPELINE_AUDIT.md`  
> 2. `.orchestrator/AUDIT_REPORTS/MEDIA_LOADING_AUDIT.md`  
> 3. `.orchestrator/AUDIT_REPORTS/LIVE_DEVICE_DIAGNOSTICS.md`  
> 4. User Directive: *"Query composite ratings - Make this an option in the gallary settings instead - on what score to use here."*  

---

## 1. Executive Summary

This revised specification consolidates all empirical findings from the live Pixel 8 diagnostics session, the data pipeline audit across 45 desktop extensions, and the media loading investigation. It establishes permanent architectural remediations and proactive feature designs across both the C# desktop export plugin and the Flutter mobile companion.

### Summary of Systemic Upgrades

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PHASE 2 REVISION OVERVIEW                       │
├───────────────────────────────────┬────────────────────────────────────┤
│ C# Desktop Export Pipeline        │ Flutter Mobile Companion App       │
├───────────────────────────────────┼────────────────────────────────────┤
│ 1. SystemChecker spec validation  │ 1. Gallery Rating Score Source pref│
│    (suppress 231 empty stubs)     │    (Composite, Critic, Comm, User) │
│ 2. SuccessStory SourcesLink &     │ 2. Achievements UI overhaul        │
│    cached icon sync               │    (Default unlocked, rarity sort) │
│ 3. DuplicateHider dynamic tag     │ 3. Microtrailer auto-fading scrub  │
│    resolution ([DH] Hidden)       │    bar & mute controls             │
│ 4. Storefront link sanitization   │ 4. GameActivity interactive charts │
│    ("Uknown" provider typo fix)   │    (Bar Histogram vs Line Chart)   │
│ 5. PluginId source attribution    │ 5. Android edge-swipe gesture fix  │
│    fallback for console titles    │ 6. Expanded 8-field sort options   │
│                                   │ 7. SharedPreferences state save    │
│                                   │ 8. Six Utility Drawer Filters      │
│                                   │ 9. Token Refresh Interceptor (401) │
│                                   │ 10. PRAGMA migration guards        │
└───────────────────────────────────┴────────────────────────────────────┘
```

---

## 2. C# Desktop Export Pipeline Specifications

### 2.1 SystemChecker Specs Validation & Empty Stub Suppression

#### Problem Analysis
`playnite-systemchecker-plugin` (`e248b230-6edf-41ea-a3c3-7861fa267263`) generated 310 JSON files in `ExtensionsData`. Exactly **79 games** have verified hardware requirements scraped from PCGamingWiki, while **231 games** contain empty dummy stub objects where `Os`, `Cpu`, and `Gpu` are empty arrays (`[]`) and `Ram` / `Storage` are `0.0`. The existing exporter forwarded these stubs, causing the mobile companion to render literal `[]` and `0.0 bytes`.

#### Specification for `SystemCheckerExtractor.cs`
Update `playnite-exporter-plugin/Addons/Extractors/SystemCheckerExtractor.cs` to introduce a strict validation predicate:

```csharp
private static bool HasRealSpecs(List<string> os, List<string> cpu, List<string> gpu, double? ram, double? storage)
{
    var hasOs = os != null && os.Any(s => !string.IsNullOrWhiteSpace(s));
    var hasCpu = cpu != null && cpu.Any(s => !string.IsNullOrWhiteSpace(s));
    var hasGpu = gpu != null && gpu.Any(s => !string.IsNullOrWhiteSpace(s));
    var hasRam = ram.HasValue && ram.Value > 0.0;
    var hasStorage = storage.HasValue && storage.Value > 0.0;

    return hasOs || hasCpu || hasGpu || hasRam || hasStorage;
}
```

#### Extraction Rules:
1. When parsing `Items` array from `{game_id}.json`, evaluate `HasRealSpecs(...)` on both minimum and recommended specs.
2. If `HasRealSpecs(...)` evaluates to `false` for an entry, treat that entry as `null`.
3. If both minimum and recommended specs are `null`, the extractor MUST return:
   ```json
   {
     "has_requirements": false,
     "minimum": null,
     "recommended": null
   }
   ```
4. Empty stubs are completely suppressed from the cloud payload, saving bandwidth and preventing blank spec cards on mobile.

---

### 2.2 SuccessStory Achievements Enhancement

#### Problem Analysis
`SuccessStoryExtractor.cs` omitted the root `SourcesLink` object, dropping storefront achievement URLs. Furthermore, 29,308 achievement icons already pre-cached on the desktop in `AppData\Roaming\Playnite\cache\SuccessStory\` were never cataloged or uploaded by `MediaProcessor.cs`, forcing mobile clients to attempt downloading from external store CDNs or display fallback lock icons. Finally, games with untracked rarity displayed false `"0.0%"` badges.

#### Specification for `SuccessStoryExtractor.cs`:
1. **Extract Storefront Link:**
   Read `SourcesLink` from the JSON root and map to `store_url` and `sources_link`:
   ```csharp
   string storeUrl = null;
   if (root.TryGetProperty("SourcesLink", out var sourcesLink) && sourcesLink.ValueKind == JsonValueKind.Object)
   {
       if (sourcesLink.TryGetProperty("Url", out var urlProp))
       {
           storeUrl = urlProp.GetString();
       }
   }
   ```
2. **Preserve Rarity & Guard `NoRarety`:**
   Inspect the `NoRarety` boolean property on each achievement item:
   ```csharp
   bool noRarity = item.TryGetProperty("NoRarety", out var nr) && nr.GetBoolean();
   double? rarityPercent = null;
   if (!noRarity && item.TryGetProperty("Percent", out var p))
   {
       rarityPercent = p.GetDouble();
   }
   ```
   If `noRarity` is `true`, serialize `rarity_percentage` as `null` rather than `0.0`.
3. **Local Icon Cache Resolution in `MediaProcessor.cs`:**
   For each achievement icon URL, compute `MD5(url).jpg` and check `PlayniteUserDataDir\cache\SuccessStory\{hash}.jpg`.
   If the icon exists locally, expose its local path or content hash so the sync engine can upload the icon to `media/achievements/{hash}.webp`, enabling 100% offline achievement browsing on mobile.

---

### 2.3 DuplicateHider Dynamic Tag Resolution & Secondary Copy Tracking

#### Problem Analysis
`MetadataAggregator.cs` relied on a hardcoded GUID `db1b6850-b7ff-45fd-bde7-72b5747ec132` for `[DH] Hidden`. If a user re-installs DuplicateHider or customizes tags, this GUID changes, breaking duplicate detection and mixing secondary multi-store copies with user-hidden games.

#### Specification for `MetadataAggregator.cs`:
1. **Dynamic Tag Lookup:**
   Query `api.Database.Tags` dynamically during plugin initialization:
   ```csharp
   private Guid GetDuplicateHiderHiddenTagId()
   {
       var tag = api.Database.Tags.FirstOrDefault(t => 
           string.Equals(t.Name, "[DH] Hidden", StringComparison.OrdinalIgnoreCase));
       return tag?.Id ?? Guid.Parse("db1b6850-b7ff-45fd-bde7-72b5747ec132");
   }
   ```
2. **Secondary Copy Classification (`is_duplicate`):**
   * Primary copy: `game.Hidden == false` AND duplicate group has $>1$ copies.
   * Secondary copy: `game.Hidden == true` AND `game.TagIds.Contains(dhHiddenTagId)`. Mark `is_duplicate = true` in `UnifiedGamePayload`.
   * User-hidden game: `game.Hidden == true` AND `!game.TagIds.Contains(dhHiddenTagId)`. Mark `is_duplicate = false`.
3. **Maintain `duplicate_group_id`:**
   Hash the normalized game title (`Regex.Replace(name.ToLowerInvariant(), @"[^a-z0-9]", "")`) to generate a deterministic UUID linking all alternate store copies of the same title.

---

### 2.4 Storefront Links Sanitization & Provider Typo Remediation

#### Problem Analysis
Upstream scraping metadata providers wrote literal `"Uknown"` (missing the 'n') into `games.db` for PlayStation and Xbox store URLs. The C# exporter forwarded this string unchanged, rendering `"Uknown"` chips on mobile.

#### Specification for `MetadataAggregator.cs`:
Add a URL domain-matching resolver when building `LinkEntity`:

```csharp
public static string SanitizeLinkName(string rawName, string url)
{
    if (!string.IsNullOrWhiteSpace(rawName) &&
        !rawName.Equals("Uknown", StringComparison.OrdinalIgnoreCase) &&
        !rawName.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
        !rawName.Equals("Store", StringComparison.OrdinalIgnoreCase))
    {
        return rawName.Trim();
    }

    if (string.IsNullOrWhiteSpace(url)) return "Link";

    if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
    {
        var host = uri.Host.ToLowerInvariant();
        if (host.Contains("playstation.com")) return "PlayStation Store";
        if (host.Contains("xbox.com") || host.Contains("microsoft.com")) return "Xbox Store";
        if (host.Contains("steampowered.com") || host.Contains("steamcommunity.com")) return "Steam";
        if (host.Contains("epicgames.com")) return "Epic Games Store";
        if (host.Contains("gog.com")) return "GOG";
        if (host.Contains("nintendo.com")) return "Nintendo eShop";
        if (host.Contains("ea.com") || host.Contains("origin.com")) return "EA App";
        if (host.Contains("ubisoft.com") || host.Contains("uplay.com")) return "Ubisoft Store";
        if (host.Contains("itch.io")) return "itch.io";
        if (host.Contains("pcgamingwiki.com")) return "PCGamingWiki";
        if (host.Contains("howlongtobeat.com")) return "HowLongToBeat";
    }

    return !string.IsNullOrWhiteSpace(rawName) ? rawName : "Store";
}
```

---

### 2.5 Console & Manual Game Source Attribution Fallback

#### Problem Analysis
Console imports (PlayStation, Xbox, Nintendo Switch, emulators) frequently have `game.SourceId == Guid.Empty`. Currently, the exporter exports `source = null`, which SQLite defaults to `"Unknown"`.

#### Specification for `MetadataAggregator.cs`:
Implement a fallback cascade when `game.SourceId == Guid.Empty`:

```csharp
NamedEntity ResolveSource(Game game)
{
    // 1. Direct SourceId mapping
    if (game.SourceId != Guid.Empty)
    {
        var src = api.Database.Sources.Get(game.SourceId);
        if (src != null) return new NamedEntity { Id = src.Id, Name = src.Name };
    }

    // 2. Library PluginId mapping
    if (game.PluginId == Guid.Parse("cb91dfc9-b977-43bf-8e70-55f46e410fab"))
        return new NamedEntity { Id = game.PluginId, Name = "Steam" };
    if (game.PluginId == Guid.Parse("00000002-dbd1-46c6-b5d0-b1ba559d10e4"))
        return new NamedEntity { Id = game.PluginId, Name = "Epic Games" };
    if (game.PluginId == Guid.Parse("00000001-ebb2-4eec-abcb-7c89937a42bb"))
        return new NamedEntity { Id = game.PluginId, Name = "GOG" };
    if (game.PluginId == Guid.Parse("7e4fbb5e-2ae3-48d4-8ba0-6b30e7a4e287"))
        return new NamedEntity { Id = game.PluginId, Name = "Xbox" };
    if (game.PluginId == Guid.Parse("c2f038e5-8b92-4877-91f1-da9094155fc5"))
        return new NamedEntity { Id = game.PluginId, Name = "Ubisoft Connect" };
    if (game.PluginId == Guid.Parse("85dd7072-2f20-4e76-a007-41035e390724"))
        return new NamedEntity { Id = game.PluginId, Name = "EA App" };

    // 3. Platform Name Fallback (e.g., "PlayStation 5" -> "PlayStation")
    var platform = game.PlatformIds?.Select(id => api.Database.Platforms.Get(id)).FirstOrDefault(p => p != null);
    if (platform != null)
    {
        if (platform.Name.Contains("PlayStation", StringComparison.OrdinalIgnoreCase))
            return new NamedEntity { Id = platform.Id, Name = "PlayStation" };
        if (platform.Name.Contains("Xbox", StringComparison.OrdinalIgnoreCase))
            return new NamedEntity { Id = platform.Id, Name = "Xbox" };
        if (platform.Name.Contains("Nintendo", StringComparison.OrdinalIgnoreCase))
            return new NamedEntity { Id = platform.Id, Name = "Nintendo" };
    }

    // 4. Storefront link domain inference
    var storeLink = game.Links?.FirstOrDefault(l => !string.IsNullOrEmpty(l.Url));
    if (storeLink != null && Uri.TryCreate(storeLink.Url, UriKind.Absolute, out var uri))
    {
        if (uri.Host.Contains("playstation.com")) return new NamedEntity { Id = Guid.Empty, Name = "PlayStation" };
        if (uri.Host.Contains("xbox.com")) return new NamedEntity { Id = Guid.Empty, Name = "Xbox" };
        if (uri.Host.Contains("steampowered.com")) return new NamedEntity { Id = Guid.Empty, Name = "Steam" };
        if (uri.Host.Contains("gog.com")) return new NamedEntity { Id = Guid.Empty, Name = "GOG" };
    }

    return null;
}
```

---

## 3. Flutter Mobile Companion Architecture & UI Updates

### 3.1 SQLite Migration Guard (`app_database.dart`)

#### Problem Analysis
Every cold startup executes six unguarded `ALTER TABLE games ADD COLUMN ...` statements in `_ensureColumnsExist()`. This triggers six native `SQLiteLog (1) duplicate column name` error logs on every launch.

#### Specification:
Update `_ensureColumnsExist` in `lib/core/database/app_database.dart` to inspect `PRAGMA table_info(games)` before running `ALTER TABLE`:

```dart
Future<void> _ensureColumnsExist(DatabaseExecutor db) async {
  final columnsRes = await db.rawQuery('PRAGMA table_info(games);');
  final existingColumns = columnsRes.map((r) => r['name'] as String).toSet();

  if (!existingColumns.contains('is_duplicate')) {
    await db.execute('ALTER TABLE games ADD COLUMN is_duplicate INTEGER NOT NULL DEFAULT 0;');
  }
  if (!existingColumns.contains('other_copies_json')) {
    await db.execute("ALTER TABLE games ADD COLUMN other_copies_json TEXT NOT NULL DEFAULT '[]';");
  }
  if (!existingColumns.contains('icon_drive_file_id')) {
    await db.execute('ALTER TABLE games ADD COLUMN icon_drive_file_id TEXT;');
  }
  if (!existingColumns.contains('icon_sha256')) {
    await db.execute('ALTER TABLE games ADD COLUMN icon_sha256 TEXT;');
  }
  if (!existingColumns.contains('trailer_web_url')) {
    await db.execute('ALTER TABLE games ADD COLUMN trailer_web_url TEXT;');
  }
  if (!existingColumns.contains('series_json')) {
    await db.execute("ALTER TABLE games ADD COLUMN series_json TEXT NOT NULL DEFAULT '[]';");
  }
}
```

---

### 3.2 Domain A4: Gallery Settings "Rating Score Source" & DAO Composite Query Fix

#### User Requirement
> *"Query composite ratings - Make this an option in the gallary settings instead - on what score to use here."*

#### Problem Analysis
Live diagnostics revealed that **0 of 1,453 games** have `user_score` populated, while **1,347 games** have `critic_score` or `community_score`. The existing query `WHERE user_score >= ?` wiped out 100% of the game collection when the slider was moved to `>0%`.

#### Architecture & Implementation:
1. **Extend `GallerySettings` Model (`gallery_settings_repository.dart`):**
   ```dart
   enum RatingScoreSource {
     composite, // COALESCE(user_score, critic_score, community_score)
     critic,    // critic_score only
     community, // community_score only
     user,      // user_score only
   }
   ```
   Add `ratingScoreSource` to `GallerySettings` with default `RatingScoreSource.composite`:
   ```dart
   class GallerySettings {
     final bool showHiddenGames;
     final String defaultViewMode;
     final RatingScoreSource ratingScoreSource;

     const GallerySettings({
       this.showHiddenGames = false,
       this.defaultViewMode = 'grid',
       this.ratingScoreSource = RatingScoreSource.composite,
     });
   }
   ```

2. **Add Preference Selector in `GallerySettingsScreen`:**
   Add a settings card under "Display Preferences":
   ```dart
   ListTile(
     title: const Text('Rating Score Source'),
     subtitle: Text(_getScoreSourceSubtitle(_settings.ratingScoreSource)),
     trailing: DropdownButton<RatingScoreSource>(
       value: _settings.ratingScoreSource,
       items: const [
         DropdownMenuItem(value: RatingScoreSource.composite, child: Text('Composite (Best Available)')),
         DropdownMenuItem(value: RatingScoreSource.critic, child: Text('Critic Score (Metacritic/OpenCritic)')),
         DropdownMenuItem(value: RatingScoreSource.community, child: Text('Community Score (Steam/IGDB)')),
         DropdownMenuItem(value: RatingScoreSource.user, child: Text('User Score (Personal Rating)')),
       ],
       onChanged: (val) {
         if (val != null) _updateSettings(_settings.copyWith(ratingScoreSource: val));
       },
     ),
   );
   ```

3. **Pass Active Score Source into `GameFilterCriteria` & `GameDao`:**
   Update `GameDao.getGames(...)` query builder:
   ```dart
   if (criteria.minScore != null || criteria.maxScore != null) {
     String scoreExpr;
     switch (criteria.ratingScoreSource) {
       case RatingScoreSource.critic:
         scoreExpr = 'critic_score';
         break;
       case RatingScoreSource.community:
         scoreExpr = 'community_score';
         break;
       case RatingScoreSource.user:
         scoreExpr = 'user_score';
         break;
       case RatingScoreSource.composite:
       default:
         scoreExpr = 'COALESCE(user_score, critic_score, community_score)';
         break;
     }

     if (criteria.minScore != null) {
       whereClauses.add('$scoreExpr IS NOT NULL AND $scoreExpr >= ?');
       whereArgs.add(criteria.minScore);
     }
     if (criteria.maxScore != null) {
       whereClauses.add('$scoreExpr IS NOT NULL AND $scoreExpr <= ?');
       whereArgs.add(criteria.maxScore);
     }
   }
   ```
   **Verification Outcome:** Moving the slider above 0% now smoothly filters games according to the user's preferred score source.

---

### 3.3 Domain B5: Achievements UI Overhaul

#### Specification for `achievements_section.dart`:
1. **Smart Initial Filter:**
   If `unlocked_count >= 1`, default the active tab to `"Unlocked"`. Otherwise, default to `"All"`.
2. **Compact 4–5 Preview Mode:**
   Initially display the top 4 achievements with a prominent expandable button:
   `"Show All {total} Achievements"` / `"Collapse"`.
3. **Multi-Criteria Sorting:**
   Provide a compact pill dropdown to sort achievements by:
   - **Unlock Date** (Most recent first).
   - **Rarity** (Rarest percentage first).
   - **GamerScore / Points** (Highest first).
   - **Alphabetical** (A to Z).
4. **Rarity Pill Guard:**
   If `rarity_percentage == null` or `no_rarity == true`, do NOT display `"0.0%"`. Display `"Rare"` if unlocked, or omit the rarity pill. Format valid rarity as `"14.2% Rare"`.
5. **Store Achievements Deep-Link Button:**
   If `store_url` is present in `addonData`, render an outline action button in the card header:
   `[ Open Store Achievements ↗ ]` launching `url_launcher`.
6. **Local Cached Icon Resolution:**
   Support local `file://` cached icons alongside remote HTTP icons using `PlayniteCachedImage`.

---

### 3.4 Domain B6: Microtrailer Video Controls

#### Specification for `microtrailer_player.dart`:
1. **Auto-Fading Touch Overlay:**
   Tapping or hovering the video player reveals an overlay containing:
   - **Play / Pause Toggle** (Center icon).
   - **Mute / Unmute Button** (Top right speaker icon).
   - **Progress Scrub Bar & Timestamp** (Bottom edge slider showing `0:02 / 0:06`).
2. **Timer-Based Auto-Fade:**
   The overlay stays visible for **3.0 seconds** after any touch interaction, then fades to 0% opacity via an `AnimatedOpacity(duration: Duration(milliseconds: 300))`.
3. **Gallery Settings Integration:**
   Read preferences from `GallerySettings`:
   - `autoPlayMicrotrailers` (bool, default: `true`).
   - `microtrailerMuted` (bool, default: `true`).
   - `showVideoScrubBar` (bool, default: `true`).
4. **Lifecycle Guard:**
   Inspect `mounted` and `!_isDisposed` before invoking `_controller.play()`, `setLooping()`, or `setVolume()` to prevent `StateError` on rapid route exit.

---

### 3.5 Domain B7: GameActivity Interactive Visualizer

#### Specification for `activity_section.dart`:
Replace the flat session list with an interactive visualization component:

```
┌────────────────────────────────────────────────────────┐
│  PLAY SESSIONS (18 Sessions, 42h 15m Total)            │
│  [ Bar Histogram ]   [ Cumulative Hours ]             │
├────────────────────────────────────────────────────────┤
│  5h ┤       █                                          │
│  4h ┤       █   █                                      │
│  3h ┤   █   █   █       █                              │
│  2h ┤   █   █   █   █   █       █                      │
│  1h ┤ █ █ █ █ █ █ █ █ █ █ █ █ █ █                      │
│     └─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴───────────────────── │
│       Oct 01       Oct 08       Oct 15                 │
├────────────────────────────────────────────────────────┤
│  ▶ Recent Sessions Log (Tap to expand all 18)          │
│    • Oct 15, 2026 — 2h 45m (Default Action)            │
│    • Oct 12, 2026 — 1h 10m (Default Action)            │
└────────────────────────────────────────────────────────┘
```

1. **View Toggle:** Segmented button switching between:
   - **Bar Histogram:** Session duration per day over the last 30 active days.
   - **Cumulative Line Chart:** Total library hours accumulated over time.
2. **Custom Painter Rendering:** High-performance, dependency-free `CustomPainter` rendering smooth curves and rounded bars at 120fps.
3. **Interactive Touch Tooltips:** Tapping any bar displays the exact date, session duration, and action name.
4. **Collapsible Session Logs:** Collapsible list showing the 5 most recent sessions with an `"Expand All ({N})"` toggle.

---

### 3.6 Domain C8: Android Edge-Swipe Back Gesture Conflict Fix

#### Problem Analysis
In Android 10+ and Android 17 gesture navigation, swiping inward from the left or right screen edge triggers system `Back`. In `library_screen.dart`, Flutter's `Scaffold.endDrawer` intercepts right-edge drags, causing gesture conflict where the filter drawer unexpectedly opens when the user intended to navigate back.

#### Specification:
In `lib/features/library/presentation/library_screen.dart`:
```dart
return Scaffold(
  key: _scaffoldKey,
  drawerEnableOpenDragGesture: false,
  endDrawerEnableOpenDragGesture: false,
  ...
);
```
Users open the filter drawer explicitly via the `IconButton(Icons.filter_list)` in the app bar. All edge-swipe gestures are surrendered to Android's system back gesture.

---

### 3.7 Domain C9: Expanded Sorting Options

#### Specification for `sort_options.dart`:
Expand `SortField` to support 8 comprehensive sorting dimensions:

```dart
enum SortField {
  title,            // sorting_name COLLATE NOCASE
  addedDate,        // added_utc
  playtime,         // playtime_seconds
  lastPlayed,       // last_activity_utc
  timesPlayed,      // play_count
  communityScore,   // community_score
  criticScore,      // critic_score
  releaseDate,      // release_date
}
```

#### SQL Order Clauses:
```dart
String toSqlOrderBy() {
  final dir = direction == SortDirection.ascending ? 'ASC' : 'DESC';
  switch (field) {
    case SortField.title:
      return 'sorting_name COLLATE NOCASE $dir';
    case SortField.addedDate:
      return 'added_utc $dir';
    case SortField.playtime:
      return 'playtime_seconds $dir';
    case SortField.lastPlayed:
      return 'last_activity_utc $dir';
    case SortField.timesPlayed:
      return 'play_count $dir';
    case SortField.communityScore:
      return 'community_score $dir';
    case SortField.criticScore:
      return 'critic_score $dir';
    case SortField.releaseDate:
      return 'release_date $dir';
  }
}
```

The sorting bottom sheet will present clean, localized labels for each field with an Ascending/Descending toggle chip.

---

### 3.8 Domain C10: Persistent Sort & Filter State in `SharedPreferences`

#### Specification:
Create a dedicated `LibraryPreferencesService` using `shared_preferences`:

```dart
class LibraryPreferencesService {
  static const _sortFieldKey = 'pref_sort_field';
  static const _sortDirectionKey = 'pref_sort_direction';
  static const _viewModeKey = 'pref_view_mode';
  static const _filterCriteriaKey = 'pref_filter_criteria_json';

  Future<void> saveSortOption(SortOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortFieldKey, option.field.name);
    await prefs.setString(_sortDirectionKey, option.direction.name);
  }

  Future<SortOption> loadSortOption() async {
    final prefs = await SharedPreferences.getInstance();
    final fieldName = prefs.getString(_sortFieldKey);
    final directionName = prefs.getString(_sortDirectionKey);

    final field = SortField.values.firstWhere(
      (f) => f.name == fieldName,
      orElse: () => SortField.title,
    );
    final direction = SortDirection.values.firstWhere(
      (d) => d.name == directionName,
      orElse: () => SortDirection.ascending,
    );

    return SortOption(field: field, direction: direction);
  }

  Future<void> saveFilterCriteria(GameFilterCriteria criteria) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterCriteriaKey, jsonEncode(criteria.toJson()));
  }

  Future<GameFilterCriteria?> loadFilterCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_filterCriteriaKey);
    if (raw == null) return null;
    return GameFilterCriteria.fromJson(jsonDecode(raw));
  }
}
```
`LibraryScreen` restores these preferences in `initState()`, ensuring users never lose their active sorting, view mode, or filters across app restarts.

---

### 3.9 Domain C11: Dedicated Utility Filters in Drawer

#### Specification:
Add a dedicated "Library Diagnostics & Utility Filters" expansion tile in `filter_drawer.dart`:

```dart
ExpansionTile(
  title: const Text('Utility & Diagnostics Filters'),
  leading: const Icon(Icons.build_circle_outlined, color: AppTheme.primaryLight),
  children: [
    CheckboxListTile(
      title: const Text('Show Hidden Only'),
      value: criteria.showHiddenOnly,
      onChanged: (v) => update(criteria.copyWith(showHiddenOnly: v ?? false)),
    ),
    CheckboxListTile(
      title: const Text('Include Hidden in Search'),
      value: criteria.includeHidden,
      onChanged: (v) => update(criteria.copyWith(includeHidden: v ?? false)),
    ),
    CheckboxListTile(
      title: const Text('Missing Cover Art'),
      value: criteria.missingCoversOnly,
      onChanged: (v) => update(criteria.copyWith(missingCoversOnly: v ?? false)),
    ),
    CheckboxListTile(
      title: const Text('DuplicateHider Secondary Copies'),
      value: criteria.duplicateCopiesOnly,
      onChanged: (v) => update(criteria.copyWith(duplicateCopiesOnly: v ?? false)),
    ),
    CheckboxListTile(
      title: const Text('Missing Microtrailers'),
      value: criteria.missingMicrotrailersOnly,
      onChanged: (v) => update(criteria.copyWith(missingMicrotrailersOnly: v ?? false)),
    ),
    CheckboxListTile(
      title: const Text('Unplayed Games (0 Hours)'),
      value: criteria.unplayedOnly,
      onChanged: (v) => update(criteria.copyWith(unplayedOnly: v ?? false)),
    ),
  ],
)
```

#### SQL Implementation in `GameDao`:
```dart
if (criteria.missingCoversOnly) {
  whereClauses.add("(cover_drive_file_id IS NULL OR cover_drive_file_id = '')");
}
if (criteria.duplicateCopiesOnly) {
  whereClauses.add("is_duplicate = 1");
}
if (criteria.missingMicrotrailersOnly) {
  whereClauses.add("(microtrailer_drive_file_id IS NULL OR microtrailer_drive_file_id = '')");
}
if (criteria.unplayedOnly) {
  whereClauses.add("(playtime_seconds = 0 OR play_count = 0)");
}
```

---

### 3.10 Domain D12: Application Branding, Identity & Adaptive Launcher Icons

#### Specification:
1. **Application Display Name:**
   - In `android/app/src/main/AndroidManifest.xml`:
     `android:label="Playnite Mobile Companion"`
   - In `ios/Runner/Info.plist`:
     `<key>CFBundleDisplayName</key><string>Playnite Companion</string>`
2. **Adaptive App Icon:**
   - Configure `flutter_launcher_icons` in `pubspec.yaml`:
     ```yaml
     flutter_launcher_icons:
       android: true
       ios: true
       image_path: "assets/branding/app_icon.png"
       adaptive_icon_background: "#181A20"
       adaptive_icon_foreground: "assets/branding/app_icon_foreground.png"
     ```
   - Foreground design: Stylized Playnite orange-to-purple gradient chevron embedded within an ergonomic modern gamepad silhouette.

---

### 3.11 Domain D13: Five Proactive UX Enhancements

1. **Alphabetical Scrub Thumb / Fast-Scroll Indexer:**
   A vertical alphabet strip (`# A B C ... Z`) along the right edge of the grid. Dragging the thumb provides haptic feedback and instantly snaps the viewport to that letter group using an indexed position lookup.
2. **"Surprise Me" Random Game Picker:**
   A Floating Action Button or AppBar icon. Tapping triggers a celebratory roulette animation that picks a random unplayed/backlog game from the current filtered set and navigates to its detail view.
3. **HowLongToBeat Target Slider Filter:**
   A dual-thumb range slider in the drawer allowing users to filter by completion time:
   `[ 0h —————●————— 20h ]` (e.g. *Find games beatable in under 20 hours*).
4. **Hero Route Transitions with Shared Image Elements:**
   Wrap the cover card in `Hero(tag: 'cover_${game.id}', child: ...)` and mirror in `GameDetailScreen` to produce fluid 120fps zoom transitions on card tap.
5. **Layered Placeholder Beneath Fade-In (Zero Black-Flash):**
   In `PlayniteCachedImage`, retain the dark placeholder container stacked behind `Image.file` inside `frameBuilder` until the raster frame decodes, completely eliminating visual flicker during rapid scroll.

---

## 4. Media Loading, Caching & Network Resilience Architecture

### 4.1 Token Refresh Interceptor in `PlayniteImageLoader`

#### Problem Analysis
Google Drive OAuth2 access tokens expire after 3,600 seconds (1 hour). When a user browses the library past 1 hour, every newly loaded image fails with `HTTP 401 Unauthorized`, leaving dark placeholder tiles across the grid.

#### Specification for `PlayniteImageLoader.dart`:
1. Register a token refresh callback:
   ```dart
   typedef TokenRefreshCallback = Future<String?> Function();
   TokenRefreshCallback? _tokenRefresher;

   void setTokenRefresher(TokenRefreshCallback callback) {
     _tokenRefresher = callback;
   }
   ```
2. Intercept HTTP 401 status in `_startDownload(key)`:
   ```dart
   final response = await request.close().timeout(const Duration(seconds: 12));
   if (response.statusCode == 401 && _tokenRefresher != null) {
     final refreshedToken = await _tokenRefresher!();
     if (refreshedToken != null && refreshedToken.isNotEmpty) {
       MediaUrlResolver.setAuthToken(refreshedToken);
       // Retry download once with new token
       return await _retryDownload(key, rawMediaId);
     }
   }
   ```
3. Wire `GoogleDriveApiService.refreshAccessToken` as the token refresher during `main.dart` initialization.

---

### 4.2 Streaming Body Timeouts & In-Flight Cancellation

#### Specification:
1. Bound both connection and body stream reading:
   ```dart
   final response = await request.close().timeout(const Duration(seconds: 12));
   final bytes = await consolidateHttpClientResponseBytes(response).timeout(const Duration(seconds: 15));
   ```
2. In `cancel(mediaId, listener)`:
   If the item is currently active in `_activeHttpRequests`, invoke `request.abort()` immediately when canceled, liberating bandwidth for visible items currently waiting in `_lifoQueue`.

---

### 4.3 Unified Background Fanart Caching & Downsampling

#### Specification:
Refactor `MicrotrailerPlayer`'s `_buildBackgroundImage` and `_buildLogo` to delegate directly to `PlayniteCachedImage`:
* Fanarts: `PlayniteCachedImage(mediaId: bgId, memCacheWidth: 1280, memCacheHeight: 720, fit: BoxFit.cover)`
* Logos: `PlayniteCachedImage(mediaId: logoId, memCacheWidth: 400, fit: BoxFit.contain)`

Background fanarts will now automatically benefit from LIFO scheduling, persistent flash caching, and 0ms offline display on subsequent views.

---

### 4.4 Local Folder Sync & Cross-Platform `file://` Resolution

#### Specification:
1. In `MediaUrlResolver`:
   * Store `static String? _localSyncPath;`
   * When resolving relative paths (`media/covers/hash.webp`):
     If `_localSyncPath != null`, return `p.join(_localSyncPath!, mediaId)`.
2. Cross-Platform File Parsing:
   Replace all string slicing `raw.substring(7)` with standard URI file resolution:
   `Uri.parse(raw).toFilePath(windows: Platform.isWindows)`
3. In `MicrotrailerPlayer`:
   If the video path is a local file, instantiate `VideoPlayerController.file(File(path))` instead of `networkUrl()`.

---

### 4.5 Cache Management UI in Gallery Settings

#### Specification:
Add a "Storage & Cache Management" card in `GallerySettingsScreen`:
* Display: **Cached Thumbnails:** `{N} images ({size_in_mb} MB)`.
* Action: **"Clear Image Cache"** button that invokes `PlayniteImageLoader.instance.clearCache()`, reclaims disk space, and updates the UI counter.
* LRU Eviction: Background task that prunes files older than 30 days if cache size exceeds **500 MB**.

---

## 5. Verification Gates & QA Sign-off Matrix

| Verification ID | Scope | Target Pass Criteria |
| :--- | :--- | :--- |
| **QA-P2-01** | SystemChecker Stubs | 0 of 231 empty games export dummy requirement objects; real specs formatted cleanly without brackets. |
| **QA-P2-02** | Score Filtering | Setting rating slider to 50% filters games using `COALESCE(user, critic, community)` with zero library wipeout. |
| **QA-P2-03** | Gallery Rating Setting | Changing "Rating Score Source" in Gallery Settings to "Critic" updates queries to `critic_score >= ?`. |
| **QA-P2-04** | Achievements Overhaul | Games with $\ge 1$ unlock default to "Unlocked" tab; rarity pill guarded against 0.0%; store deep-link operational. |
| **QA-P2-05** | Video Controls | Microtrailer tap reveals mute toggle and scrub bar; fades out automatically after 3.0 seconds. |
| **QA-P2-06** | Android Edge Swipes | Swiping left/right edge on Android 17 navigates Back without triggering the filter drawer. |
| **QA-P2-07** | Expanded Sorting | All 8 sort fields sort database rows accurately in both Ascending and Descending directions. |
| **QA-P2-08** | Preference Persistence | App restart preserves last active sort field, view mode, and applied filters. |
| **QA-P2-09** | Token Refresh | Expired Bearer token triggers automatic refresh; image loading succeeds without rendering error placeholders. |
| **QA-P2-10** | SQLite Startup Log | Cold launch produces zero `duplicate column name` SQLite native error logs. |

---

*End of Phase 2 Revised Architecture Specification.*
