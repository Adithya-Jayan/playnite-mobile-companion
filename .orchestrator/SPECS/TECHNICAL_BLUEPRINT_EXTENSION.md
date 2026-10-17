# Technical Blueprint: Playnite Desktop Exporter Plugin (`playnite-exporter-plugin`)

> **Specification Version:** 1.0.0  
> **Author:** Architect-Agent (Phase 2: Lead Systems Architect)  
> **Target Framework:** .NET 6.0 (C# 10) / Playnite SDK 10 (with .NET 4.6.2 / Playnite 9 compatibility notes)  
> **Target Project Name:** `PlayniteExporterPlugin`  
> **Audience:** Master Orchestrator, Spec-Verifier-Agent, Playnite-Plugin-Lead-Agent (Phase 3)  
> **Status:** APPROVED FOR IMPLEMENTATION  

---

## 1. Architecture Overview & Design Goals

The `playnite-exporter-plugin` is an in-process Playnite desktop plugin inheriting from `GenericPlugin`. It is responsible for observing game state changes, aggregating metadata across Playnite's internal database and installed extensions, executing high-performance content-addressable delta hashing, and incrementally pushing deltas to Google Drive.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PLAYNITE HOST RUNTIME                           │
│                                                                        │
│   Playnite.DesktopApp.exe (.NET 6.0 Runtime)                           │
│   ├── PlayniteApi.Database (In-memory Game cache & secondary tables)   │
│   └── Playnite SDK Lifecycle Events                                    │
│        ├── OnApplicationStarted                                        │
│        ├── OnLibraryUpdated                                            │
│        └── OnGameStopped                                               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Hooks
┌───────────────────────────────────▼────────────────────────────────────┐
│                  PLAYNITE EXPORTER PLUGIN ARCHITECTURE                 │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     Plugin Lifecycle Entry                     │   │
│   │                 (PlayniteExporterPlugin.cs)                    │   │
│   └───────────────┬───────────────────────────────┬────────────────┘   │
│                   │ Event Trigger                 │ Settings / UI      │
│   ┌───────────────▼──────────────┐  ┌─────────────▼────────────────┐   │
│   │      ExportCoordinator       │  │    SettingsView (WPF/XAML)   │   │
│   └───────────────┬──────────────┘  └──────────────────────────────┘   │
│                   │                                                    │
│   ┌───────────────▼──────────────┐  ┌──────────────────────────────┐   │
│   │      MetadataAggregator      │◄─┤    IAddonDataExtractor       │   │
│   │                              │  │    Registry (Whitelist)      │   │
│   └───────────────┬──────────────┘  └──────────────────────────────┘   │
│                   │ UnifiedGamePayload                                 │
│   ┌───────────────▼──────────────┐                                     │
│   │       DeltaHashEngine        │                                     │
│   │ (SHA-256 + Diff vs Cached)   │                                     │
│   └───────────────┬──────────────┘                                     │
│                   │ SyncDiff (Added, Modified, Deleted, Unchanged)     │
│   ┌───────────────▼──────────────┐                                     │
│   │    GoogleDriveSyncClient     │                                     │
│   │  (OAuth2, Drive v3, Polly)   │                                     │
│   └───────────────┬──────────────┘                                     │
└───────────────────┼────────────────────────────────────────────────────┘
                    │ HTTPS REST (Scoped drive.file)
┌───────────────────▼────────────────────────────────────────────────────┐
│                    GOOGLE DRIVE CLOUD STORAGE                          │
│                                                                        │
│   PlayniteSync/                                                        │
│   ├── sync_index.json                                                  │
│   ├── manifest.json                                                    │
│   ├── games/{game_id}.json                                             │
│   └── media/{covers|backgrounds|logos|microtrailers}                   │
└────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Key Architectural Decisions
1. **In-Process SDK Execution:** Rather than reading locked LiteDB files out-of-process, the plugin runs inside `Playnite.DesktopApp.exe`. It uses `PlayniteApi.Database.Games` directly from memory, guaranteeing $100\%$ file concurrency safety and zero lock contention.
2. **Resilient Addon Extractor Registry:** Addon data is gathered through isolated `IAddonDataExtractor` implementations. Any missing, disabled, corrupted, or newly installed addon never breaks library export.
3. **Deterministic Serialization:** JSON serialization enforces sorted object keys and invariant culture formatting, ensuring that identical data produces identical SHA-256 hashes across runs.
4. **Resumable Atomic Commit:** Uploads utilize chunked resumable streams for videos and finalize with an atomic overwrite of `sync_index.json`.

---

## 2. Solution Directory Structure

```
playnite-exporter-plugin/
├── extension.yaml                           # Playnite extension manifest
├── PlayniteExporterPlugin.csproj            # .NET 6.0 SDK project
├── PlayniteExporterPlugin.cs                # Plugin lifecycle entry & SDK overrides
│
├── Configuration/
│   ├── ExporterSettings.cs                  # User preferences model (serializable)
│   ├── ExporterSettingsViewModel.cs         # Observable ViewModel for settings
│   └── SecureTokenStorage.cs                # DPAPI Windows credential encryption
│
├── Models/
│   ├── UnifiedGamePayload.cs                # POCO mapping to GAME_PAYLOAD_SCHEMA.json
│   ├── ManifestPayload.cs                   # POCO for manifest.json
│   ├── SyncIndex.cs                         # POCO for sync_index.json root index
│   ├── IndexEntry.cs                        # File metadata entry in index
│   └── SyncDiff.cs                          # Added, Modified, Deleted, Unchanged sets
│
├── Services/
│   ├── ExportCoordinator.cs                 # Orchestrates aggregation, diffing, and upload
│   ├── MetadataAggregator.cs                # Maps Playnite Game + Addons -> UnifiedGamePayload
│   ├── DeltaHashEngine.cs                   # SHA-256 calculation & index comparison
│   ├── MediaProcessor.cs                    # Cover/Background hash, WebP detection, sizing
│   └── DriveSync/
│       ├── GoogleDriveSyncClient.cs         # Drive v3 REST API wrapper
│       ├── GoogleAuthService.cs             # Local loopback OAuth2 listener (Port 51734)
│       └── DriveFolderHierarchy.cs          # Caches folder IDs (PlayniteSync, games, media)
│
├── Addons/
│   ├── IAddonDataExtractor.cs               # Extensibility contract
│   ├── AddonExtractorRegistry.cs            # Discovers and invokes all registered extractors
│   └── Extractors/
│       ├── SuccessStoryExtractor.cs         # Achievements & unlocked percentage
│       ├── HowLongToBeatExtractor.cs        # Playtime completion estimates (in seconds)
│       ├── GameActivityExtractor.cs         # Session tracking logs
│       ├── ExtraMetadataExtractor.cs        # Logos, microtrailers, full trailers
│       ├── CheckDlcExtractor.cs             # DLC listings, pricing, ownership
│       ├── SystemCheckerExtractor.cs        # Hardware minimum/recommended specs
│       └── SteamReviewsExtractor.cs         # Steam store review percentages
│
└── Views/
    ├── SettingsView.xaml                    # WPF configuration dialog
    ├── SettingsView.xaml.cs                 # Code-behind
    ├── SyncProgressDialog.xaml              # Real-time sync modal for manual runs
    └── SyncProgressDialog.xaml.cs
```

---

## 3. Playnite SDK Hooks & Event Lifecycle

The plugin hooks into key SDK lifecycle events to provide automatic, invisible delta synchronization.

```csharp
public class PlayniteExporterPlugin : GenericPlugin
{
    private static readonly ILogger logger = LogManager.GetLogger();
    private readonly ExporterSettingsViewModel settings;
    private readonly ExportCoordinator coordinator;

    public PlayniteExporterPlugin(IPlayniteAPI api) : base(api)
    {
        settings = new ExporterSettingsViewModel(this);
        Properties = new GenericPluginProperties
        {
            HasSettings = true
        };

        var authService = new GoogleAuthService(settings);
        var driveClient = new GoogleDriveSyncClient(authService, settings);
        coordinator = new ExportCoordinator(api, settings.Settings, driveClient);
    }

    public override void OnApplicationStarted(OnApplicationStartedEventArgs args)
    {
        // 1. Validate local index cache integrity in background thread
        // 2. Refresh OAuth2 tokens if expired
        Task.Run(async () =>
        {
            try
            {
                await coordinator.InitializeAsync();
            }
            catch (Exception ex)
            {
                logger.Error(ex, "Failed to initialize exporter coordinator.");
            }
        });
    }

    public override void OnGameStopped(OnGameStoppedEventArgs args)
    {
        // TARGETED O(1) ATOMIC SYNC
        if (!settings.Settings.AutoSyncOnGameStopped) return;

        var game = args.Game;
        logger.Info($"Game stopped: {game.Name} ({game.Id}). Enqueuing atomic delta sync.");

        // Dispatch background export for this single game
        Task.Run(async () =>
        {
            await coordinator.SyncSingleGameAsync(game);
        });
    }

    public override void OnLibraryUpdated(OnLibraryUpdatedEventArgs args)
    {
        // BULK LIBRARY UPDATE SYNC
        if (!settings.Settings.AutoSyncOnLibraryUpdated) return;

        logger.Info("Library update detected. Enqueuing incremental delta sync.");
        Task.Run(async () =>
        {
            await coordinator.SyncIncrementalLibraryAsync();
        });
    }

    public override IEnumerable<MainMenuItem> GetMainMenuItems(GetMainMenuItemsArgs args)
    {
        return new List<MainMenuItem>
        {
            new MainMenuItem
            {
                Description = "Sync Library to Google Drive",
                MenuSection = "@Playnite Mobile Sync",
                Action = _ => coordinator.ShowManualSyncDialog()
            },
            new MainMenuItem
            {
                Description = "Force Full Re-Export & Upload",
                MenuSection = "@Playnite Mobile Sync",
                Action = _ => coordinator.ShowForceFullExportDialog()
            }
        };
    }
}
```

---

## 4. Extensible Addon Registry & Safe Extraction

### 4.1 Extractor Interface Contract
To satisfy the critical requirement that **adding, removing, or corrupting addons must never break the sync system**, all addon readers implement `IAddonDataExtractor`:

```csharp
public interface IAddonDataExtractor
{
    /// <summary>
    /// Unique identifier key matching GAME_PAYLOAD_SCHEMA.json 'addons' property.
    /// Example: "success_story", "how_long_to_beat"
    /// </summary>
    string AddonKey { get; }

    /// <summary>
    /// Human-readable name for logging and UI.
    /// </summary>
    string DisplayName { get; }

    /// <summary>
    /// The Playnite Plugin GUID or folder name in ExtensionsData/.
    /// </summary>
    Guid PluginId { get; }

    /// <summary>
    /// Checks if the extension data folder exists and contains files.
    /// </summary>
    bool IsDataAvailable(string extensionsDataPath);

    /// <summary>
    /// Extracts addon data for the target game. Must return null if no data exists.
    /// MUST NOT throw unhandled exceptions.
    /// </summary>
    Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir);
}
```

### 4.2 Registry Implementation with Error Boundaries
The `AddonExtractorRegistry` isolates every extractor call inside a structured `try/catch` boundary. If an extractor throws an unexpected parsing error, the failure is logged as a non-fatal warning, returning `null` for that specific addon while allowing the rest of the game's data to export cleanly:

```csharp
public class AddonExtractorRegistry
{
    private static readonly ILogger logger = LogManager.GetLogger();
    private readonly List<IAddonDataExtractor> extractors = new();

    public AddonExtractorRegistry()
    {
        // Register known built-in extractors (Whitelisted approach)
        Register(new SuccessStoryExtractor());
        Register(new HowLongToBeatExtractor());
        Register(new GameActivityExtractor());
        Register(new ExtraMetadataExtractor());
        Register(new CheckDlcExtractor());
        Register(new SystemCheckerExtractor());
        Register(new SteamReviewsExtractor());
    }

    public void Register(IAddonDataExtractor extractor)
    {
        extractors.Add(extractor);
    }

    public async Task<Dictionary<string, object?>> ExtractAllAsync(Game game, string userDataDir)
    {
        var results = new Dictionary<string, object?>();

        foreach (var extractor in extractors)
        {
            try
            {
                var data = await extractor.ExtractDataAsync(game, userDataDir);
                if (data != null)
                {
                    results[extractor.AddonKey] = data;
                }
            }
            catch (Exception ex)
            {
                logger.Warn(ex, $"Failed extracting addon data '{extractor.DisplayName}' for game '{game.Name}' ({game.Id}). Skipping addon.");
                // Graceful degradation: do NOT throw; continue to next addon
            }
        }

        return results;
    }
}
```

### 4.3 Concrete Extractor Sample: `HowLongToBeatExtractor`
Notice how durations are strictly preserved in seconds, and disabled extensions with historical data are handled safely:

```csharp
public class HowLongToBeatExtractor : IAddonDataExtractor
{
    public string AddonKey => "how_long_to_beat";
    public string DisplayName => "HowLongToBeat";
    public Guid PluginId => Guid.Parse("e08cd51f-9c9a-4ee3-a094-fde03b55492f");

    public bool IsDataAvailable(string extensionsDataPath)
    {
        var dir = Path.Combine(extensionsDataPath, PluginId.ToString(), "HowLongToBeat");
        return Directory.Exists(dir);
    }

    public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
    {
        var filePath = Path.Combine(
            playniteUserDataDir,
            "ExtensionsData",
            PluginId.ToString(),
            "HowLongToBeat",
            $"{game.Id}.json"
        );

        if (!File.Exists(filePath)) return null;

        string jsonContent;
        using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        using (var reader = new StreamReader(stream))
        {
            jsonContent = await reader.ReadToEndAsync();
        }

        using var doc = JsonDocument.Parse(jsonContent);
        var root = doc.RootElement;

        if (!root.TryGetProperty("Items", out var items) || items.GetArrayLength() == 0)
        {
            return null;
        }

        var firstItem = items[0];
        if (!firstItem.TryGetProperty("GameHltbData", out var hltbData))
        {
            return null;
        }

        return new
        {
            has_data = true,
            hltb_id = firstItem.TryGetProperty("Id", out var idProp) ? idProp.GetString() : null,
            url = firstItem.TryGetProperty("Url", out var urlProp) ? urlProp.GetString() : null,
            main_story_seconds = hltbData.TryGetProperty("MainStoryClassic", out var ms) ? ms.GetInt64() : 0,
            main_extra_seconds = hltbData.TryGetProperty("MainExtraClassic", out var me) ? me.GetInt64() : 0,
            completionist_seconds = hltbData.TryGetProperty("CompletionistClassic", out var c) ? c.GetInt64() : 0,
            solo_seconds = hltbData.TryGetProperty("SoloClassic", out var s) ? s.GetInt64() : 0,
            coop_seconds = hltbData.TryGetProperty("CoOpClassic", out var cp) ? cp.GetInt64() : 0,
            vs_seconds = hltbData.TryGetProperty("VsClassic", out var vs) ? vs.GetInt64() : 0
        };
    }
}
```

---

## 5. Metadata Aggregator & Payload Generation

The `MetadataAggregator` translates the in-memory `Playnite.SDK.Models.Game` entity into `UnifiedGamePayload`.

```csharp
public class MetadataAggregator
{
    private readonly IPlayniteAPI api;
    private readonly AddonExtractorRegistry addonRegistry;
    private readonly MediaProcessor mediaProcessor;

    public MetadataAggregator(IPlayniteAPI api, AddonExtractorRegistry addonRegistry, MediaProcessor mediaProcessor)
    {
        this.api = api;
        this.addonRegistry = addonRegistry;
        this.mediaProcessor = mediaProcessor;
    }

    public async Task<UnifiedGamePayload> BuildGamePayloadAsync(Game game)
    {
        var userDataDir = api.Paths.ConfigurationPath;

        // Resolve relational references
        var source = game.SourceId != Guid.Empty ? api.Database.Sources.Get(game.SourceId) : null;
        var status = game.CompletionStatusId != Guid.Empty ? api.Database.CompletionStatuses.Get(game.CompletionStatusId) : null;
        var platforms = game.PlatformIds?.Select(id => api.Database.Platforms.Get(id)).Where(p => p != null).ToList();
        var genres = game.GenreIds?.Select(id => api.Database.Genres.Get(id)).Where(g => g != null).ToList();
        var devs = game.DeveloperIds?.Select(id => api.Database.Companies.Get(id)).Where(c => c != null).ToList();
        var pubs = game.PublisherIds?.Select(id => api.Database.Companies.Get(id)).Where(c => c != null).ToList();
        var tags = game.TagIds?.Select(id => api.Database.Tags.Get(id)).Where(t => t != null).ToList();

        // Process media assets (SHA-256 and dimensions)
        var media = await mediaProcessor.ResolveGameMediaAsync(game, userDataDir);

        // Extract addons
        var addons = await addonRegistry.ExtractAllAsync(game, userDataDir);

        return new UnifiedGamePayload
        {
            SchemaVersion = "1.0.0",
            Id = game.Id,
            GameId = game.GameId ?? string.Empty,
            PluginId = game.PluginId,
            Name = game.Name,
            SortingName = string.IsNullOrWhiteSpace(game.SortingName) ? game.Name : game.SortingName,
            Description = game.Description,
            Notes = game.Notes,
            PlaytimeSeconds = (long)game.Playtime,
            PlayCount = (long)game.PlayCount,
            AddedUtc = game.Added?.ToUniversalTime(),
            ModifiedUtc = game.Modified?.ToUniversalTime(),
            LastActivityUtc = game.LastActivity?.ToUniversalTime(),
            RecentActivityUtc = game.RecentActivity?.ToUniversalTime(),
            ReleaseDate = game.ReleaseDate?.ToString(),
            IsInstalled = game.IsInstalled,
            InstallDirectory = game.InstallDirectory,
            InstallSizeBytes = (long?)game.InstallSize,
            Hidden = game.Hidden,
            Favorite = game.Favorite,
            Version = game.Version,
            UserScore = game.UserScore,
            CriticScore = game.CriticScore,
            CommunityScore = game.CommunityScore,
            Source = source != null ? new NamedEntity { Id = source.Id, Name = source.Name } : null,
            CompletionStatus = status != null ? new NamedEntity { Id = status.Id, Name = status.Name } : null,
            Platforms = platforms?.Select(p => new PlatformEntity { Id = p.Id, Name = p.Name, SpecId = p.SpecificationId }).ToList() ?? new(),
            Genres = genres?.Select(g => new NamedEntity { Id = g.Id, Name = g.Name }).ToList() ?? new(),
            Developers = devs?.Select(d => new NamedEntity { Id = d.Id, Name = d.Name }).ToList() ?? new(),
            Publishers = pubs?.Select(p => new NamedEntity { Id = p.Id, Name = p.Name }).ToList() ?? new(),
            Tags = tags?.Select(t => new NamedEntity { Id = t.Id, Name = t.Name }).ToList() ?? new(),
            Links = game.Links?.Select(l => new LinkEntity { Name = l.Name, Url = l.Url }).ToList() ?? new(),
            Media = media,
            Addons = addons
        };
    }
}
```

---

## 6. Delta Hash Engine & Diff Calculation

The `DeltaHashEngine` performs byte-level content hashing and compares the generated payloads against the local cached `sync_index.json`.

```csharp
public class DeltaHashEngine
{
    private static readonly JsonSerializerOptions jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public string ComputeStringSha256(string content)
    {
        using var sha256 = SHA256.Create();
        var bytes = Encoding.UTF8.GetBytes(content);
        var hash = sha256.ComputeHash(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public string ComputeFileSha256(string filePath)
    {
        using var sha256 = SHA256.Create();
        using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var hash = sha256.ComputeHash(stream);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public SyncDiff ComputeDiff(
        Dictionary<string, (string content, string sha256, long size, string category, Guid? gameId)> candidateFiles,
        SyncIndex previousIndex)
    {
        var diff = new SyncDiff();

        // Check for Added and Modified items
        foreach (var (path, candidate) in candidateFiles)
        {
            if (!previousIndex.Entries.TryGetValue(path, out var existing))
            {
                diff.Added.Add(new PlannedUpload(path, candidate.content, candidate.sha256, candidate.size, candidate.category, candidate.gameId));
            }
            else if (!string.Equals(candidate.sha256, existing.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                diff.Modified.Add(new PlannedUpload(path, candidate.content, candidate.sha256, candidate.size, candidate.category, candidate.gameId, existing.DriveFileId));
            }
            else
            {
                diff.Unchanged.Add(path, existing);
            }
        }

        // Check for Deleted items
        foreach (var (existingPath, existing) in previousIndex.Entries)
        {
            if (!candidateFiles.ContainsKey(existingPath))
            {
                diff.Deleted.Add(new PlannedDeletion(existingPath, existing.DriveFileId, existing.Category));
            }
        }

        return diff;
    }
}
```

---

## 7. Google Drive Client Architecture

### 7.1 Scoped Authentication (OAuth2 Loopback)
The plugin interacts with Google Drive using the `drive.file` scope. It uses an embedded HTTP loopback listener (`http://127.0.0.1:51734/callback`) to receive the authorization code, exchanges it for an access token and refresh token, and encrypts the tokens with the Windows Data Protection API (DPAPI):

```csharp
public class SecureTokenStorage
{
    private readonly string tokenFilePath;

    public SecureTokenStorage(string pluginUserDataDir)
    {
        tokenFilePath = Path.Combine(pluginUserDataDir, "drive_auth.dat");
    }

    public void SaveEncryptedToken(string tokenJson)
    {
        var plainBytes = Encoding.UTF8.GetBytes(tokenJson);
        var encryptedBytes = ProtectedData.Protect(
            plainBytes,
            optionalEntropy: null,
            DataProtectionScope.CurrentUser
        );
        File.WriteAllBytes(tokenFilePath, encryptedBytes);
    }

    public string? LoadDecryptedToken()
    {
        if (!File.Exists(tokenFilePath)) return null;

        var encryptedBytes = File.ReadAllBytes(tokenFilePath);
        var plainBytes = ProtectedData.Unprotect(
            encryptedBytes,
            optionalEntropy: null,
            DataProtectionScope.CurrentUser
        );
        return Encoding.UTF8.GetString(plainBytes);
    }
}
```

### 7.2 Fault-Tolerant Drive Service with Polly Retries
All API calls are executed through a Polly resilience pipeline handling HTTP 429 (Quota Exhaustion) and HTTP 503 (Service Unavailable):

```csharp
public class GoogleDriveSyncClient
{
    private static readonly ILogger logger = LogManager.GetLogger();
    private readonly DriveService driveService;
    private readonly AsyncPolicy retryPolicy;

    public GoogleDriveSyncClient(DriveService driveService)
    {
        this.driveService = driveService;

        // Exponential backoff with jitter
        retryPolicy = Policy
            .Handle<GoogleApiException>(ex => ex.HttpStatusCode == HttpStatusCode.TooManyRequests || (int)ex.HttpStatusCode >= 500)
            .Or<HttpRequestException>()
            .WaitAndRetryAsync(
                retryCount: 5,
                sleepDurationProvider: retryAttempt => 
                    TimeSpan.FromSeconds(Math.Pow(2, retryAttempt)) + TimeSpan.FromMilliseconds(Random.Shared.Next(0, 1000)),
                onRetry: (exception, timespan, retryCount, context) =>
                {
                    logger.Warn($"Google Drive API throttle/failure. Retrying {retryCount}/5 after {timespan.TotalSeconds:N1}s. Error: {exception.Message}");
                }
            );
    }

    public async Task<string> UploadFileAsync(
        string fileName,
        string mimeType,
        Stream stream,
        string parentFolderId,
        string? existingFileId = null,
        IProgress<long>? progress = null)
    {
        return await retryPolicy.ExecuteAsync(async () =>
        {
            var driveFile = new Google.Apis.Drive.v3.Data.File
            {
                Name = fileName,
                MimeType = mimeType,
                Parents = existingFileId == null ? new List<string> { parentFolderId } : null
            };

            if (existingFileId != null)
            {
                // Update existing file
                var updateRequest = driveService.Files.Update(driveFile, existingFileId, stream, mimeType);
                updateRequest.Fields = "id, name, size, md5Checksum";
                if (progress != null)
                {
                    updateRequest.ProgressChanged += p => progress.Report(p.BytesSent);
                }
                var result = await updateRequest.UploadAsync();
                if (result.Status == Google.Apis.Upload.UploadStatus.Failed)
                {
                    throw result.Exception;
                }
                return updateRequest.ResponseBody.Id;
            }
            else
            {
                // Create new file
                var createRequest = driveService.Files.Create(driveFile, stream, mimeType);
                createRequest.Fields = "id, name, size, md5Checksum";
                if (progress != null)
                {
                    createRequest.ProgressChanged += p => progress.Report(p.BytesSent);
                }
                var result = await createRequest.UploadAsync();
                if (result.Status == Google.Apis.Upload.UploadStatus.Failed)
                {
                    throw result.Exception;
                }
                return createRequest.ResponseBody.Id;
            }
        });
    }
}
```

---

## 8. Settings View & Configuration (WPF / XAML)

The plugin provides a native WPF settings interface embedded inside Playnite's Settings menu.

```
┌────────────────────────────────────────────────────────────────────────┐
│ PLAYNITE MOBILE EXPORTER SETTINGS                                      │
├────────────────────────────────────────────────────────────────────────┤
│ Google Drive Connection                                                │
│ Account: user@gmail.com [Connected]              [Disconnect Account] │
│ Target Cloud Folder: PlayniteSync/               [Browse...]           │
│ Storage Quota: 12.4 GB / 15.0 GB used (82%)      [Check Quota]         │
├────────────────────────────────────────────────────────────────────────┤
│ Automated Delta Sync Triggers                                          │
│ [X] Sync on Game Exit (OnGameStopped - Instant O(1) single-game update)│
│ [X] Sync on Library Update (OnLibraryUpdated)                          │
│ [ ] Sync on Playnite Startup                                           │
├────────────────────────────────────────────────────────────────────────┤
│ Media Synchronization Policy                                           │
│ [X] Sync Game Covers (Optimized WebP, 600x900)                         │
│ [X] Sync Game Backgrounds (Fanart, 1920x1080)                          │
│ [X] Sync Transparent Game Logos (ExtraMetadata PNG)                    │
│ [X] Sync Microtrailers (6-second 60fps video loop, ~2 MB each)         │
│ [ ] Sync Full Cinematic Trailers (HD video, ~40 MB each - Not Rec.)    │
├────────────────────────────────────────────────────────────────────────┤
│ Performance & Network Quotas                                           │
│ Max Parallel Upload Connections: [ 4 ] (1 - 8)                         │
│ [X] Enable Orphan Pruning (Trash unreferenced files on cloud)          │
├────────────────────────────────────────────────────────────────────────┤
│ Manual Actions                                                         │
│ [ Sync Now (Incremental Delta) ]    [ Force Full Re-Export & Upload ]  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Error Handling & Recovery Strategies

| Failure Mode | Detection | Plugin Mitigation | Result |
|---|---|---|---|
| **Addon Uninstalled / Folder Deleted** | `Directory.Exists` check fails | Extractor safely returns `null` | Game exports without that addon; zero crash. |
| **Addon JSON Corrupted / Unreadable** | `JsonException` caught in extractor boundary | Logs non-fatal warning; returns `null` | Core game metadata + other healthy addons export successfully. |
| **Google Drive Token Expired** | `GoogleApiException` (401 Unauthorized) | Auto-refreshes using DPAPI refresh token; retries once | Seamless operation without prompting user. |
| **Network Dropped During Video Upload** | `IOException` or `SocketException` | Resumable chunked upload restarts from last byte offset | Bandwidth preserved; resumes on next attempt. |
| **App Closed Mid-Sync** | Process termination | Cloud retains previous valid `sync_index.json` | Mobile companion reads previous consistent state; zero corruption. |

---

## 10. Verification Gates for Phase 3 Implementation
1. **Initial Full Export Test:** Verify that cold-start export generates 100% compliant `manifest.json`, `sync_index.json`, and per-game JSON documents.
2. **No-Op Delta Test:** Running sync without playing games must verify `0 bytes uploaded` and `0 API calls` for game payloads.
3. **Single-Game Atomic Update Test:** Launching and stopping 1 game must upload exactly 1 game payload, update `sync_index.json`, and complete in $< 1.5\text{ seconds}$.
4. **Addon Hot-Removal Test:** Disabling `SuccessStory` must allow sync to complete successfully without errors.
