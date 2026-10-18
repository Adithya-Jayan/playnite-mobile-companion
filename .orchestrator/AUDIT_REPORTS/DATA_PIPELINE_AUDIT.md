# Phase 1 Data Pipeline, Addon Audit & Export Integrity

**Author:** Data-Pipeline-Auditor-Agent  
**Date:** October 18, 2026  
**Target:** `playnite-exporter-plugin` (C#), `playnite-mobile-companion` (Dart), and Playnite User Data (`ExtensionsData`)  
**Status:** COMPLETE AUDIT & REMEDIATION SPECIFICATION  

---

## Executive Summary

A comprehensive architectural, data-level, and code-level audit was conducted across the Playnite data pipeline, installed desktop addons, and the mobile companion synchronization engine. 

The audit inspected Playnite's `ExtensionsData` (under strict read-only guarantees), the C# export pipeline (`playnite-exporter-plugin`), and the Flutter/Dart mobile client (`playnite-mobile-companion`). The investigation uncovered **five major data pipeline failure points** causing UI breakages, empty spec panels, missing achievement icons, incorrect storefront labeling, and library wipeout on rating filters.

### Key Findings Summary Matrix

| Subsystem | Severity | Primary Root Causes | Manifestation in Mobile App |
| :--- | :---: | :--- | :--- |
| **SystemChecker / Specs** | **HIGH** | `SystemCheckerExtractor.cs` does not validate hardware spec lists before exporting dummy stub objects; Dart UI iterates empty map entries without formatting. | Requirements card shows literal `[]` and `0.0 bytes` on 231 games; valid specs display raw unformatted JSON arrays. |
| **SuccessStory / Achievements** | **HIGH** | `SuccessStoryExtractor.cs` omits `SourcesLink`; `MediaProcessor.cs` does not sync cached achievement icons (`cache\SuccessStory\`); non-HTTP URLs fail Dart check. | Offline achievements show generic fallback lock/check icons; non-HTTP icons fail to render; missing store achievement links. |
| **DuplicateHider / Grouping** | **MEDIUM** | Hardcoded `DuplicateHiderHiddenTagId` GUID in C#; reflection checks look for nonexistent method signatures; missing tag metadata resolution. | Fragile duplicate detection; inability to distinguish user-hidden games from auto-hidden duplicate copies across diverse database installs. |
| **Links & Storefronts** | **MEDIUM** | Scraping metadata providers write literal typo `"Uknown"` in Playnite's `games.db`; C# exporter blindly forwards name; missing domain inference. | PlayStation and Xbox store links render as `"Uknown"` chips; games without explicit `SourceId` fall back to `"Unknown"`. |
| **Rating Scale (>0 Filter)** | **CRITICAL** | `game_dao.dart` queries `user_score >= ?` in SQLite; `user_score` is `NULL` for unrated games in Playnite; completely ignores `critic_score` and `community_score`. | Adjusting score slider to any value `>0` immediately filters out 100% of the game library. |

---

## 1. SystemChecker & Hardware Requirements Audit

### 1.1 ExtensionsData Analysis
* **Extension ID:** `e248b230-6edf-41ea-a3c3-7861fa267263` (`playnite-systemchecker-plugin` by Lacro59).
* **Storage Path:** `C:\Users\adith\AppData\Roaming\Playnite\ExtensionsData\e248b230-6edf-41ea-a3c3-7861fa267263\`
* **Data Inventory:**
  * `SystemChecker.db`: LiteDB database storing hardware requirements cache.
  * `SystemChecker/<game-guid>.json`: 310 individual game JSON files in library.
  * `Configurations.json`: Machine hardware configuration (`MS_MANGO`, 12th Gen Intel i7-12700H, NVIDIA RTX 3060 Laptop GPU, 16 GB RAM).
  * `config.json`: Extension settings (auto-import, source exclusions).
* **Data Distribution in Library:**
  * **79 games:** Populated with real requirements scraped from PCGamingWiki (e.g. *Sol Cesto*, *Cyberpunk 2077*).
  * **231 games:** Empty stub files created by SystemChecker before scraping or when PCGamingWiki has no entry.

#### Raw Stub Payload in ExtensionsData (Empty Games):
```json
{
  "Items": [
    {
      "IsMinimum": true,
      "Os": [],
      "Cpu": [],
      "Gpu": [],
      "Ram": 0.0,
      "RamUsage": "0.0 bytes",
      "Storage": 0.0,
      "StorageUsage": "0.0 bytes"
    },
    {
      "IsMinimum": false,
      "Os": [],
      "Cpu": [],
      "Gpu": [],
      "Ram": 0.0,
      "RamUsage": "0.0 bytes",
      "Storage": 0.0,
      "StorageUsage": "0.0 bytes"
    }
  ],
  "DateLastRefresh": "0001-01-01T00:00:00",
  "GameExist": true,
  "Id": "025d800e-7c15-4bfb-a2da-302759196f31",
  "Name": "KAMI"
}
```

### 1.2 C# SystemCheckerExtractor.cs Flaw
In `playnite-exporter-plugin\Addons\Extractors\SystemCheckerExtractor.cs`:
```csharp
foreach (var token in itemsArray)
{
    if (token is not JObject item) continue;

    var isMin = item.Value<bool?>("IsMinimum") ?? true;
    var osList = ToStringList(item["Os"]);
    var cpuList = ToStringList(item["Cpu"]);
    var gpuList = ToStringList(item["Gpu"]);
    var ramBytes = item.Value<double?>("Ram");
    var ramUsage = item.Value<string>("RamUsage");
    var storageBytes = item.Value<double?>("Storage");
    var storageUsage = item.Value<string>("StorageUsage");

    var specObj = new
    {
        os = osList,
        cpu = cpuList,
        gpu = gpuList,
        ram_bytes = ramBytes,
        ram_usage = ramUsage,
        storage_bytes = storageBytes,
        storage_usage = storageUsage
    };

    if (isMin && minSpecs == null) minSpecs = specObj;
    else if (!isMin && recSpecs == null) recSpecs = specObj;
}

return new
{
    has_requirements = minSpecs != null || recSpecs != null,
    minimum = minSpecs,
    recommended = recSpecs
};
```

**Root Cause:**
1. Because `itemsArray` contains two stub elements, `minSpecs` and `recSpecs` are non-null objects containing empty arrays and `0.0`.
2. `has_requirements` evaluates to `true`.
3. The extractor exports a full `system_checker` object with zero actual requirement data.

### 1.3 Dart Mobile UI Rendering Flaw
In `playnite-mobile-companion\lib\features\game_detail\presentation\addon_registry\sections\requirements_section.dart`:
```dart
final minimum = addonData['minimum'] as Map<String, dynamic>? ?? {};
final recommended = addonData['recommended'] as Map<String, dynamic>? ?? {};

if (minimum.isEmpty && recommended.isEmpty) {
  return const SizedBox.shrink();
}
```
1. `minimum` has 7 keys (`os`, `cpu`, `gpu`, `ram_bytes`, `ram_usage`, `storage_bytes`, `storage_usage`). Therefore `minimum.isEmpty` is `false`.
2. The card is rendered for 231 empty games.
3. In `_buildSpecsGrid`, entries are rendered as:
   * `key`: `entry.key.replaceAll('_', ' ').toUpperCase()`
   * `val`: `entry.value.toString()`
4. For games with no specs, it prints:
   * `OS: []`
   * `CPU: []`
   * `GPU: []`
   * `RAM BYTES: 0.0`
   * `RAM USAGE: 0.0 bytes`
   * `STORAGE BYTES: 0.0`
   * `STORAGE USAGE: 0.0 bytes`
5. For games with valid specs, it prints literal array representations like `CPU: [1 GHz processor]` and displays duplicate rows for raw bytes and formatted usage.

### 1.4 CheckLocalizations (CheckLocal)
`playnite-checklocalizations-plugin` (often termed CheckLocal) is an optional Lacro59 extension for language audio/subtitles. It is not currently active in this user environment, but any future extractor must guard against null references when reading its local cache.

---

## 2. SuccessStory (Achievements) Audit

### 2.1 ExtensionsData Analysis
* **Extension ID:** `cebe6d32-8c46-4459-b993-5a5189d60788` (`playnite-successstory-plugin` by Lacro59).
* **Storage Path:** `C:\Users\adith\AppData\Roaming\Playnite\ExtensionsData\cebe6d32-8c46-4459-b993-5a5189d60788\`
* **JSON Count:** 1,566 achievement databases.
* **Cache Storage Location:** `C:\Users\adith\AppData\Roaming\Playnite\cache\SuccessStory\` (contains **29,308 cached achievement image files**).
* **Cache Key Formula:** `MD5(url).jpg` (or without extension). For example:
  * URL: `https://steamcdn-a.akamaihd.net/steamcommunity/public/images/apps/1486630/cedef5f78a8b4c9db63a4606ab802083c787a9fb.jpg`
  * Cache File: `C:\Users\adith\AppData\Roaming\Playnite\cache\SuccessStory\fec48105fd69dd4ebc0b425913fdf77f.jpg`

### 2.2 Root Causes of Missing Achievement Icons
1. **No Cloud Sync for Achievement Media:**
   `MediaProcessor.cs` only inspects and plans uploads for covers, backgrounds, icons, and logo assets. It completely ignores `C:\Users\adith\AppData\Roaming\Playnite\cache\SuccessStory\`.
2. **Non-HTTP Icon URLs:**
   Several games (such as miHoYo launchers, Zenless Zone Zero, Genshin Impact, and emulator titles) store local relative paths in SuccessStory:
   * `5c0d0b31-fb90-4f63-8f47-07f5a4d857d0.json` -> `"UrlUnlocked": "ZenlessZoneZero\\ac.png"`
   * `9a140dcf-2ddf-47ef-bd9b-63096d21323b.json` -> `"UrlUnlocked": "GenshinImpact\\ac.png"`
3. **Dart Image Loader Bypass:**
   In `achievements_section.dart`:
   ```dart
   child: (iconUrl != null && iconUrl.startsWith('http'))
       ? PlayniteCachedImage(mediaId: iconUrl, ...)
       : Icon(isUnlocked ? Icons.check_circle : Icons.lock)
   ```
   * All non-HTTP icons are immediately skipped and show generic lock/check icons.
   * When offline, HTTP icons fail to download if not already cached on the mobile device, ignoring the fact that the desktop Playnite instance already had 29,308 icons pre-cached.

### 2.3 Rarity Percentages & Store Achievement Links
1. **Omitted `SourcesLink`:**
   Each SuccessStory JSON contains a top-level `SourcesLink`:
   ```json
   "SourcesLink": {
     "Name": "Epic",
     "GameName": "Sunless Sea",
     "Url": "https://www.epicgames.com/store/en-US/achievements/sunless-sea"
   }
   ```
   `SuccessStoryExtractor.cs` completely ignores this property, dropping the store achievements link from the payload.
2. **False Ultra-Rare Rarity Display:**
   Games that do not track global rarity percentages have `Percent: 0.0` or `"NoRarety": true`. The mobile UI naively formats this as `0.0%`, leading users to believe every untracked achievement is ultra-rare.

---

## 3. DuplicateHider & Multi-Store Game Grouping

### 3.1 ExtensionsData Analysis
* **Extension ID:** `382f8003-8ed0-4e47-ae93-05b43c9c6c32` (`felixkmh_DuplicateHider_Plugin`).
* **Settings File:** `ExtensionsData\382f8003-8ed0-4e47-ae93-05b43c9c6c32\config.json`.
* **Configured Tag Mappings:**
  ```json
  "HiddenTagId": "db1b6850-b7ff-45fd-bde7-72b5747ec132",
  "RevealedTagId": "4584ccb9-1a4a-48b1-a1c7-4921bbcceaf8",
  "HighPrioTagId": "7e221fc4-0ce4-4d42-aeec-904a79445b32",
  "LowPrioTagId": "4e1bda71-382c-4694-b7bb-ea4c4ccd06d9"
  ```
* **Grouping & Sorting Pipeline:**
  * DuplicateHider builds an in-memory index `Index: Dictionary<string, List<Guid>>` using normalized game names.
  * Copies are ordered according to user priority rules:
    1. `IsInstalled` (Installed copies prioritized).
    2. `SourceId` (Priority order: Steam > GOG > Epic > Xbox > Playnite > EA > Ubisoft > Riot...).
    3. `ReleaseDate` / `Added`.
  * `copies[0]` is designated as the primary copy and remains visible (`Hidden = false`).
  * `copies[1..N]` are designated duplicate secondary copies: DuplicateHider sets `Hidden = true` AND applies the tag `[DH] Hidden` (`HiddenTagId`).

### 3.2 Distinguishing User-Hidden Games vs Duplicate Copies
To ensure reliable library presentation on mobile:
* **User-Hidden Games:** `game.Hidden == true`, but does NOT contain `[DH] Hidden` tag and does NOT match a duplicate group.
* **Duplicate-Hidden Copies:** `game.Hidden == true` AND contains `[DH] Hidden` (or belongs to a secondary copy index).
* **Primary Duplicate Copy:** `game.Hidden == false` AND has `otherCopies.isNotEmpty`.

### 3.3 C# Exporter Defects
In `MetadataAggregator.cs`:
1. `private static readonly Guid DuplicateHiderHiddenTagId = Guid.Parse("db1b6850-b7ff-45fd-bde7-72b5747ec132");`  
   **Defect:** Hardcoding this GUID causes detection to break if the tag was generated under a different GUID or deleted/recreated. The exporter should dynamically find the tag named `"[DH] Hidden"` from `api.Database.Tags`.
2. Reflection calls invoke `GetOtherCopies(Game)`, which succeeds when DuplicateHider is running in the same Playnite process. However, if the reflection fails, the fallback only checks exact normalized names without respecting DuplicateHider's source priority rules.

---

## 4. Links & Storefront Attribution Audit

### 4.1 Root Cause of "Uknown" / "Unknown" Links
An examination of raw binary records in `games.db` revealed the exact origin of this issue:
```
Context: ... BTC8BR7V276X   Name: "Uknown"   Url: "https://store.playstation.com/en-us/concept/10002926" ...
Context: ... BSLX1RNXR6H7   Name: "Uknown"   Url: "https://store.playstation.com/en-us/concept/200472" ...
Context: ... 227190        Name: "Uknown"   Url: "https://www.xbox.com/en-us/games/s..." ...
```

1. **Typo in Upstream Metadata Providers:**
   Metadata providers (such as community IGDB/Steam scrapers or importer scripts) literally wrote `"Uknown"` (missing the 'n') as the link `Name` when adding links for PlayStation and Xbox store pages.
2. **Zero Exporter Sanitization:**
   In `MetadataAggregator.cs`:
   ```csharp
   links.Add(new LinkEntity { Name = link.Name ?? string.Empty, Url = link.Url });
   ```
   The C# exporter passes the string through unchanged.
3. **Zero Client-Side Domain Resolution:**
   In Flutter `external_links_card.dart`:
   ```dart
   label: Text(link.name.isNotEmpty ? link.name : 'Link')
   ```
   Because `link.name` is `"Uknown"`, it renders a chip reading `"Uknown"`. Neither C# nor Dart inspects the URL domain to correct it.

### 4.2 Missing Source Attribution on Console Games
* For many PlayStation, Xbox, and emulated titles, `game.SourceId` is `Guid.Empty`.
* `MetadataAggregator.cs` resolves sources solely through `game.SourceId`.
* When `game.SourceId == Guid.Empty`:
  * `source` is set to `null`.
  * In SQLite: `source_name` is `NULL`.
  * In `stats_dao.dart`: `COALESCE(source_name, 'Unknown')` forces the storefront to appear as `"Unknown"`.
* **Fix Required:** If `game.SourceId == Guid.Empty`, resolve source from `game.PluginId` (built-in Xbox library is `7e4fbb5e-2ae3-48d4-8ba0-6b30e7a4e287`), or fall back to platform name (`PlayStation 5`, `Xbox Series X`), or infer from store link domain.

---

## 5. Rating Scale (>0 Filter Bug) Audit

### 5.1 Playnite Rating Architecture
Playnite tracks three distinct numeric ratings (0 to 100):
1. `UserScore`: Manually assigned by the user. **Almost always `null` in real libraries.**
2. `CriticScore`: Metacritic or OpenCritic score imported from metadata.
3. `CommunityScore`: Steam community or IGDB rating percentage.

### 5.2 The >0 Library Wipeout Bug
In `playnite-mobile-companion\lib\features\library\presentation\widgets\filter_drawer.dart`:
* The slider is presented as a general "Minimum Score" slider (0% to 100%).
* When adjusted to `> 0`, it assigns `criteria.minScore = _minScore.toInt()`.

In `playnite-mobile-companion\lib\core\database\daos\game_dao.dart`:
```dart
// 6. Filter: User Score Range
if (criteria.minScore != null) {
  whereClauses.add('user_score >= ?');
  whereArgs.add(criteria.minScore);
}
```

**Fatal Flaw:**
* In SQLite, any comparison with `NULL` returns `FALSE` or `NULL`.
* Because `user_score` is `NULL` on unrated games, `user_score >= 5` evaluates to false on virtually the entire library.
* The query ignores `critic_score` and `community_score`.
* **Result:** Moving the slider above 0 immediately causes all games to disappear from the library.

---

## 6. Comprehensive Installed Addons Inventory

A full audit of `C:\Users\adith\AppData\Roaming\Playnite\ExtensionsData\` yielded 45 extension data folders:

| Folder / GUID | Extension Name | Author | Data Contained | Export Pipeline Status |
| :--- | :--- | :--- | :--- | :--- |
| `00000001-ebb2-4eec-abcb-7c89937a42bb` | GOG Library | Playnite | Config & auth tokens | Built-in source |
| `00000002-dbd1-46c6-b5d0-b1ba559d10e4` | Epic Games Library | Playnite | Catalog cache (3,021 files) | Built-in source |
| `000001db-dbd1-46c6-b5d0-b1ba559d10e4` | Itch.io Library | Playnite | Config & tokens | Built-in source |
| `05234f92-39d3-4432-98c1-6f37a3e4b870` | EA App / Origin | Playnite | Config & auth | Built-in source |
| `14bd031a-a1ff-4754-a586-0b9c23a6f557` | StartPage | felixkmh | Layout templates | Desktop UI only |
| `2661ddac-946a-4fee-ba80-3ece762cb64b` | GOG Second Class Game Watcher | Community | GOG games watchlist | Desktop UI only |
| `382f8003-8ed0-4e47-ae93-05b43c9c6c32` | DuplicateHider | felixkmh | Tag IDs & priority list | Integrated via `MetadataAggregator` |
| `3dbe2ee4-d6c9-4c09-b377-7a086369603e` | PlayerActivities | Lacro59 | 627 friend activity records | Integrated via `PlayerActivitiesExtractor` |
| `5d65902f-9bd9-44f9-b647-04f349622bb8` | MobyGames Metadata | Playnite | Genre & category mappings | Metadata provider |
| `5f2dfd12-5f13-46fe-bcdd-64eb53ace26a` | GeForce NOW Enabler | Community | GFN database cache | Metadata provider |
| `705fdbca-e1fc-4004-b839-1d040b8b4429` | Extra Metadata Loader | Community | Logos, videos, Steam appdetails | Integrated via `ExtraMetadataExtractor` |
| `7e4fbb5e-2ae3-48d4-8ba0-6b30e7a4e287` | Xbox Library | Playnite | PFN info cache, Xbox login | Built-in source |
| `85dd7072-2f20-4e76-a007-41035e390724` | Battle.net Library | Playnite | Install manifests | Built-in source |
| `8e77fe31-5e62-41e2-8fa2-64844cfd5b6b` | Steam Screenshots Viewer | Community | 3,806 screenshots (344 MB) | Integrated via `SteamScreenshotsExtractor` |
| `a4c15d63-9ab4-4d96-9a0c-8f9b35d43a1f` | Game Relations | Community | Sequel/prequel links | Available for future extractor |
| `afbb1a0d-04a1-4d0c-9afa-c6e42ca855b4` | GameActivity | Lacro59 | 1,339 gameplay session files | Integrated via `GameActivityExtractor` |
| `bf78d9af-6e79-4c73-aca6-c23a11a485ae` | CheckDlc | Lacro59 | 1,367 DLC database files | Integrated via `CheckDlcExtractor` |
| `c2f038e5-8b92-4877-91f1-da9094155fc5` | Ubisoft Connect Library | Playnite | Config & tokens | Built-in source |
| `c6c8276f-91bf-48e5-a1d1-4bee0b493488` | Screenshots Visualizer | Lacro59 | 305 screenshot entries | Available for future extractor |
| `ca24e37a-76d9-49bf-89ab-d3cba4a54bd1` | Steam Reviews Viewer | Community | `reviewsDatabase.db` | Integrated via `SteamReviewsExtractor` |
| `cb91dfc9-b977-43bf-8e70-55f46e410fab` | Steam Library | Playnite | Steam tags & keys | Built-in source |
| `cebe6d32-8c46-4459-b993-5a5189d60788` | SuccessStory | Lacro59 | 1,566 achievement files | Integrated via `SuccessStoryExtractor` |
| `d2039edd-78f5-47c5-b190-72afef560fbe` | ThemeExtras | felixkmh | Banners, LinkIconCache (331 favicons) | Favicon source for external links |
| `d3b07384-d113-4c90-951b-10f88a91a92a` | Mobile Delta Sync Exporter | Custom | Our plugin config & sync index | Core Exporter |
| `d8c4f435-2bd2-49d8-98f6-87b1d415934a` | Splash Screen | Community | Config & splash settings | Desktop UI only |
| `e053a9fe-117f-40fd-ab46-0e09ac442ca9` | Free Game Notifications | Community | Config & notified giveaways | Desktop UI only |
| `e08cd51f-9c9a-4ee3-a094-fde03b55492f` | HowLongToBeat | Lacro59 | 671 HLTB play completion files | Integrated via `HowLongToBeatExtractor` |
| `e248b230-6edf-41ea-a3c3-7861fa267263` | SystemChecker | Lacro59 | 310 hardware spec files | Integrated via `SystemCheckerExtractor` |
| `ec2f4013-17e6-428a-b8a9-5e34a3b80009` | ThemeModifier | Lacro59 | Theme colors & layout | Desktop UI only |
| `StoresData` | Aggregated Store Cache | Playnite | EA, Epic, Steam DLC & Catalog (54 MB) | Store data cache |

---

## 7. Concrete Remediation Specifications

### 7.1 SystemChecker Fix Specification
1. **C# `SystemCheckerExtractor.cs` Validation:**
   ```csharp
   private static bool HasRealSpecs(List<string> os, List<string> cpu, List<string> gpu, double? ram, double? storage)
   {
       return (os != null && os.Count > 0) ||
              (cpu != null && cpu.Count > 0) ||
              (gpu != null && gpu.Count > 0) ||
              (ram.HasValue && ram.Value > 0) ||
              (storage.HasValue && storage.Value > 0);
   }
   ```
   Only assign `minSpecs` and `recSpecs` if `HasRealSpecs(...)` returns true.
   If both are null, return `new { has_requirements = false, minimum = (object?)null, recommended = (object?)null }`.

2. **Dart `requirements_section.dart` Presentation:**
   * Filter out keys with zero values (`0.0 bytes`, `0.0`) and empty lists.
   * Format lists into clean comma-separated strings (stripping bracket syntax).
   * Format RAM and storage using human-readable strings (`16 GB`, `50 GB`).

### 7.2 SuccessStory Achievement Icons & Links Fix Specification
1. **C# `SuccessStoryExtractor.cs` Enhancement:**
   * Extract `SourcesLink` from the JSON root and expose it as `sources_link` and `store_url`.
   * Check for cached achievement icons in `cache\SuccessStory\<md5>.jpg` and export local file references or plan media uploads.
2. **Dart `achievements_section.dart` Enhancement:**
   * Support non-HTTP local file URIs and local cached icons.
   * Guard against `Percent == 0.0` when `NoRarety == true`, rendering `"N/A"` or omitting the rarity tag rather than displaying `"0.0%"`.
   * Display a direct button to `store_url` if present.

### 7.3 DuplicateHider Robustness Specification
1. **Dynamic Tag Lookup:**
   In `MetadataAggregator.cs`, resolve the tag named `"[DH] Hidden"` from `api.Database.Tags.FirstOrDefault(...)` rather than relying on a hardcoded GUID.
2. **Distinguish Secondary Copies:**
   Ensure `is_duplicate = true` is strictly applied to secondary hidden copies, allowing mobile to separate user-hidden titles from multi-store alternate copies.

### 7.4 Link Normalization & Domain Inference Specification
1. **Domain-Based Name Resolution:**
   Implement a shared normalizer across C# and Dart:
   ```dart
   String resolveStorefrontName(String rawName, String url) {
     if (rawName.isNotEmpty && rawName != 'Uknown' && rawName != 'Unknown' && rawName != 'Store') {
       return rawName;
     }
     final uri = Uri.tryParse(url);
     if (uri == null) return rawName;
     final host = uri.host.toLowerCase();
     if (host.contains('playstation.com')) return 'PlayStation Store';
     if (host.contains('xbox.com') || host.contains('microsoft.com')) return 'Xbox Store';
     if (host.contains('steampowered.com') || host.contains('steamcommunity.com')) return 'Steam';
     if (host.contains('epicgames.com')) return 'Epic Games Store';
     if (host.contains('gog.com')) return 'GOG';
     if (host.contains('nintendo.com')) return 'Nintendo eShop';
     return rawName.isNotEmpty ? rawName : 'Link';
   }
   ```
2. **Fallback Source Attribution:**
   If `game.SourceId == Guid.Empty`, match `game.PluginId` against known platform GUIDs or infer source from the primary store link.

### 7.5 Score Filtering (>0 Bug) Specification
In `game_dao.dart`:
Replace the restrictive `user_score >= ?` clause with a composite score evaluation:
```sql
-- Composite score query: matches any rating (User, Critic, or Community)
(
  (user_score IS NOT NULL AND user_score >= ?) OR
  (critic_score IS NOT NULL AND critic_score >= ?) OR
  (community_score IS NOT NULL AND community_score >= ?)
)
```
Or allow users to choose their active rating filter dimension (Aggregate, Critic, Community, or User Score) in the filter drawer.
