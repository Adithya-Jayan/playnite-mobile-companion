using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Storage;

namespace PlayniteExporterPlugin.Services
{
    public class ExportCoordinator
    {
        private static readonly ILogger Logger = LogManager.GetLogger();

        private readonly IPlayniteAPI api;
        private readonly ExporterSettings settings;
        private readonly MetadataAggregator aggregator;
        private readonly DeltaHashEngine hashEngine;
        private readonly string pluginUserDataDir;
        private readonly string localIndexCachePath;

        private ISyncStorageProvider storageProvider;
        private SyncIndex currentIndex = new();
        private readonly SemaphoreSlim syncLock = new(1, 1);
        private readonly Dictionary<Guid, (ulong Playtime, ulong PlayCount, string Cover, string Bg, string Icon)> gameStatCache = new();

        public SyncIndex CurrentIndex => currentIndex;
        public ISyncStorageProvider StorageProvider => storageProvider;
        public bool IsSyncInProgress => syncLock.CurrentCount == 0;

        public ExportCoordinator(
            IPlayniteAPI api,
            ExporterSettings settings,
            MetadataAggregator aggregator,
            DeltaHashEngine hashEngine,
            ISyncStorageProvider storageProvider,
            string pluginUserDataDir)
        {
            this.api = api;
            this.settings = settings;
            this.aggregator = aggregator;
            this.hashEngine = hashEngine;
            this.storageProvider = storageProvider;
            this.pluginUserDataDir = pluginUserDataDir;

            if (!Directory.Exists(pluginUserDataDir))
            {
                Directory.CreateDirectory(pluginUserDataDir);
            }
            localIndexCachePath = Path.Combine(pluginUserDataDir, "sync_index.json");
        }

        public void SetStorageProvider(ISyncStorageProvider provider)
        {
            storageProvider = provider ?? throw new ArgumentNullException(nameof(provider));
        }

        public async Task InitializeAsync(CancellationToken ct = default)
        {
            await syncLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                if (File.Exists(localIndexCachePath))
                {
                    try
                    {
                        var json = File.ReadAllText(localIndexCachePath, Encoding.UTF8);
                        var loaded = DeterministicJsonSerializer.Deserialize<SyncIndex>(json);
                        if (loaded != null)
                        {
                            currentIndex = loaded;
                            Logger.Info($"Loaded cached sync_index.json with {currentIndex.Entries.Count} entries.");
                            return;
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Failed loading local sync_index.json cache. Falling back to fresh index.");
                    }
                }

                // Fallback: try download from storage provider if authenticated
                if (storageProvider.IsAuthenticated)
                {
                    using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    timeoutCts.CancelAfter(TimeSpan.FromSeconds(15));
                    try
                    {
                        await storageProvider.InitializeAsync(timeoutCts.Token).ConfigureAwait(false);
                        using var stream = await storageProvider.DownloadFileAsync("sync_index.json", null, timeoutCts.Token).ConfigureAwait(false);
                        if (stream != null)
                        {
                            using var reader = new StreamReader(stream, Encoding.UTF8);
                            var json = await reader.ReadToEndAsync().ConfigureAwait(false);
                            var loaded = DeterministicJsonSerializer.Deserialize<SyncIndex>(json);
                            if (loaded != null)
                            {
                                currentIndex = loaded;
                                File.WriteAllText(localIndexCachePath, json, Encoding.UTF8);
                                Logger.Info($"Restored sync_index.json from remote storage with {currentIndex.Entries.Count} entries.");
                                return;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Remote sync_index.json not found, timed out, or unreadable. Initializing blank index.");
                    }
                }
                else
                {
                    Logger.Info($"Storage provider '{storageProvider.ProviderName}' is not authenticated. Skipping remote index restore.");
                }

                currentIndex = new SyncIndex
                {
                    LibraryId = settings.LibraryId != Guid.Empty ? settings.LibraryId : Guid.NewGuid()
                };
                settings.LibraryId = currentIndex.LibraryId;
            }
            finally
            {
                syncLock.Release();
            }
        }

        /// <summary>
        /// TARGETED O(1) ATOMIC SINGLE-GAME DELTA SYNC
        /// Modifies ONLY games/{game.Id}.json, media if changed, and commits sync_index.json.
        /// </summary>
        public async Task<bool> SyncSingleGameAsync(
            Game game,
            IProgress<ExportProgressReport>? progress = null,
            CancellationToken ct = default)
        {
            if (game == null) return false;

            if (!storageProvider.IsAuthenticated)
            {
                var msg = storageProvider.ProviderName == "GoogleDrive"
                    ? "Google Drive authentication required. Please connect your Google account in Extension Settings or select Local Folder Sync."
                    : "Storage provider is not configured or authenticated.";
                Logger.Warn(msg);
                throw new InvalidOperationException(msg);
            }

            await syncLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                ct.ThrowIfCancellationRequested();
                progress?.Report(new ExportProgressReport($"Aggregating metadata for {game.Name}...", 0, 4));
                var userDataDir = api.Paths?.ConfigurationPath ?? pluginUserDataDir;
                var (payload, mediaUploads) = await aggregator.BuildGamePayloadAsync(game, userDataDir).ConfigureAwait(false);

                var jsonContent = DeterministicJsonSerializer.Serialize(payload);
                var sha256 = Sha256Hasher.ComputeStringHash(jsonContent);
                var sizeBytes = Encoding.UTF8.GetByteCount(jsonContent);
                var relPath = $"games/{game.Id}.json";

                var candidates = new Dictionary<string, PlannedUpload>
                {
                    [relPath] = new PlannedUpload(
                        relPath,
                        jsonContent,
                        sha256,
                        sizeBytes,
                        "game_metadata",
                        game.Id,
                        existingDriveFileId: null,
                        mimeType: "application/json"
                    )
                };

                // Add candidate media
                foreach (var media in mediaUploads)
                {
                    if (!candidates.ContainsKey(media.RelativePath))
                    {
                        candidates[media.RelativePath] = media;
                    }
                }

                // Check diff against current index (without checking deletions for other games)
                var diff = hashEngine.ComputeDiff(candidates, currentIndex, detectDeletions: false);

                // If no game changes and no media changes, no-op!
                if (diff.Added.Count == 0 && diff.Modified.Count == 0)
                {
                    Logger.Info($"SyncSingleGameAsync: Game {game.Name} ({game.Id}) is up-to-date. No-op.");
                    progress?.Report(new ExportProgressReport($"Game {game.Name} is already up to date.", 4, 4));
                    return true;
                }

                await storageProvider.InitializeAsync(ct).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();

                // 1. Upload Added/Modified media
                var allUploads = diff.Added.Concat(diff.Modified).ToList();
                var mediaItems = allUploads.Where(u => u.Category != "game_metadata" && u.Category != "manifest").ToList();
                var gamePayloads = allUploads.Where(u => u.Category == "game_metadata").ToList();

                var concurrencyLimit = Math.Max(1, Math.Min(settings.MaxParallelUploads, 8));
                using var semaphore = new SemaphoreSlim(concurrencyLimit);

                // Upload Game JSON
                progress?.Report(new ExportProgressReport($"Uploading game: {game.Name}...", 1, 4));
                foreach (var gameUpload in gamePayloads)
                {
                    ct.ThrowIfCancellationRequested();
                    using var ms = new MemoryStream(Encoding.UTF8.GetBytes(gameUpload.Content));
                    var fileId = await storageProvider.UploadFileAsync(
                        gameUpload.RelativePath,
                        gameUpload.MimeType,
                        ms,
                        gameUpload.ExistingDriveFileId,
                        null,
                        ct
                    ).ConfigureAwait(false);

                    lock (currentIndex.Entries)
                    {
                        currentIndex.Entries[gameUpload.RelativePath] = new IndexEntry
                        {
                            Sha256 = gameUpload.Sha256,
                            SizeBytes = gameUpload.SizeBytes,
                            ModifiedUtc = DateTime.UtcNow,
                            DriveFileId = fileId,
                            MimeType = gameUpload.MimeType,
                            Category = gameUpload.Category,
                            GameId = gameUpload.GameId
                        };
                    }
                }

                // Upload Media
                if (mediaItems.Count > 0)
                {
                    int mediaDone = 0;
                    var mediaTasks = mediaItems.Select(async item =>
                    {
                        await semaphore.WaitAsync(ct).ConfigureAwait(false);
                        try
                        {
                            ct.ThrowIfCancellationRequested();
                            var curMedia = Interlocked.Increment(ref mediaDone);
                            progress?.Report(new ExportProgressReport($"Uploading media {curMedia}/{mediaItems.Count}...", curMedia, mediaItems.Count));

                            if (!string.IsNullOrEmpty(item.SourceFilePath) && File.Exists(item.SourceFilePath))
                            {
                                using var fs = new FileStream(item.SourceFilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                                var fileId = await storageProvider.UploadFileAsync(
                                    item.RelativePath,
                                    item.MimeType,
                                    fs,
                                    item.ExistingDriveFileId,
                                    null,
                                    ct
                                ).ConfigureAwait(false);

                                lock (currentIndex.Entries)
                                {
                                    currentIndex.Entries[item.RelativePath] = new IndexEntry
                                    {
                                        Sha256 = item.Sha256,
                                        SizeBytes = item.SizeBytes,
                                        ModifiedUtc = DateTime.UtcNow,
                                        DriveFileId = fileId,
                                        MimeType = item.MimeType,
                                        Category = item.Category,
                                        GameId = item.GameId
                                    };
                                }
                            }
                        }
                        finally
                        {
                            semaphore.Release();
                        }
                    });

                    await Task.WhenAll(mediaTasks).ConfigureAwait(false);
                }

                ct.ThrowIfCancellationRequested();

                // 3. Update & Upload manifest.json
                var allGames = api.Database?.Games?.ToList() ?? new List<Game> { game };
                var manifest = aggregator.BuildManifest(allGames, userDataDir);
                var manifestJson = DeterministicJsonSerializer.Serialize(manifest);
                var manifestSha = Sha256Hasher.ComputeStringHash(manifestJson);
                var manifestBytes = Encoding.UTF8.GetByteCount(manifestJson);

                string? existingManifestId = currentIndex.Entries.TryGetValue("manifest.json", out var mEntry)
                    ? mEntry.DriveFileId
                    : null;

                using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(manifestJson)))
                {
                    var manifestFileId = await storageProvider.UploadFileAsync(
                        "manifest.json",
                        "application/json",
                        ms,
                        existingManifestId,
                        null,
                        ct
                    ).ConfigureAwait(false);

                    currentIndex.Entries["manifest.json"] = new IndexEntry
                    {
                        Sha256 = manifestSha,
                        SizeBytes = manifestBytes,
                        ModifiedUtc = DateTime.UtcNow,
                        DriveFileId = manifestFileId,
                        MimeType = "application/json",
                        Category = "manifest",
                        GameId = null
                    };
                }

                // 4. Atomic Commit: assemble and upload sync_index.json LAST
                string destName = storageProvider.ProviderName == "GoogleDrive" ? "Google Drive" : storageProvider.ProviderName;
                progress?.Report(new ExportProgressReport($"Committing sync_index.json to {destName}...", 4, 4, indeterminate: true));
                await CommitSyncIndexAsync(ct).ConfigureAwait(false);

                settings.LastSyncUtc = DateTime.UtcNow;
                progress?.Report(new ExportProgressReport($"Sync complete for {game.Name}.", 4, 4));
                return true;
            }
            finally
            {
                syncLock.Release();
            }
        }



        /// <summary>
        /// BULK INCREMENTAL LIBRARY SYNC
        /// Scans all games, detects modified or new items, uploads changes, and commits index last.
        /// </summary>
        public async Task<SyncDiff> SyncIncrementalLibraryAsync(
            IProgress<ExportProgressReport>? progress = null,
            CancellationToken ct = default)
        {
            if (!storageProvider.IsAuthenticated)
            {
                var msg = storageProvider.ProviderName == "GoogleDrive"
                    ? "Google Drive authentication required. Please connect your Google account in Extension Settings or select Local Folder Sync."
                    : "Storage provider is not configured or authenticated.";
                Logger.Warn(msg);
                throw new InvalidOperationException(msg);
            }

            await syncLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                ct.ThrowIfCancellationRequested();
                var games = api.Database?.Games?.ToList() ?? new List<Game>();
                var userDataDir = api.Paths?.ConfigurationPath ?? pluginUserDataDir;
                int total = games.Count;
                var scanEstimator = new ProgressEstimator(total);

                // Step 0: Ensure progress is reported immediately at step 0
                progress?.Report(new ExportProgressReport(scanEstimator.Format(0, $"Checking library games (0/{total})...", "Step 1/3: Analyzing Library"), 0, total));

                var candidateFiles = new Dictionary<string, PlannedUpload>(StringComparer.OrdinalIgnoreCase);
                var concurrencyLimit = Math.Max(1, Math.Min(settings.MaxParallelUploads, 8));

                // Pre-index existing media by GameId for fast lookups
                var existingMediaByGame = new Dictionary<Guid, List<KeyValuePair<string, IndexEntry>>>();
                if (currentIndex?.Entries != null)
                {
                    foreach (var kvp in currentIndex.Entries)
                    {
                        if (kvp.Value.GameId.HasValue && kvp.Value.Category != "game_metadata")
                        {
                            if (!existingMediaByGame.TryGetValue(kvp.Value.GameId.Value, out var list))
                            {
                                list = new List<KeyValuePair<string, IndexEntry>>();
                                existingMediaByGame[kvp.Value.GameId.Value] = list;
                            }
                            list.Add(kvp);
                        }
                    }
                }

                int scanned = 0;
                foreach (var game in games)
                {
                    ct.ThrowIfCancellationRequested();

                    var relPath = $"games/{game.Id}.json";
                    bool isUnchanged = false;
                    IndexEntry? existingEntry = null;

                    if (currentIndex != null && currentIndex.Entries.TryGetValue(relPath, out existingEntry))
                    {
                        if (!string.IsNullOrEmpty(existingEntry.Sha256) && existingEntry.ModifiedUtc > DateTime.MinValue)
                        {
                            bool metadataUnchanged = false;
                            if (game.Modified.HasValue)
                            {
                                metadataUnchanged = game.Modified.Value.ToUniversalTime() <= existingEntry.ModifiedUtc;
                            }
                            else if (game.Added.HasValue)
                            {
                                metadataUnchanged = game.Added.Value.ToUniversalTime() <= existingEntry.ModifiedUtc;
                            }
                            else
                            {
                                metadataUnchanged = true;
                            }

                            bool activityUnchanged = !game.LastActivity.HasValue ||
                                                     game.LastActivity.Value.ToUniversalTime() <= existingEntry.ModifiedUtc;

                            if (metadataUnchanged && activityUnchanged)
                            {
                                if (gameStatCache.TryGetValue(game.Id, out var stats))
                                {
                                    if (stats.Playtime == game.Playtime &&
                                        stats.PlayCount == game.PlayCount &&
                                        stats.Cover == (game.CoverImage ?? "") &&
                                        stats.Bg == (game.BackgroundImage ?? "") &&
                                        stats.Icon == (game.Icon ?? ""))
                                    {
                                        isUnchanged = true;
                                    }
                                }
                                else
                                {
                                    isUnchanged = true;
                                }
                            }
                        }
                    }

                    if (isUnchanged && existingEntry != null)
                    {
                        gameStatCache[game.Id] = (game.Playtime, game.PlayCount, game.CoverImage ?? "", game.BackgroundImage ?? "", game.Icon ?? "");

                        candidateFiles[relPath] = new PlannedUpload(
                            relPath,
                            string.Empty,
                            existingEntry.Sha256,
                            existingEntry.SizeBytes,
                            "game_metadata",
                            game.Id,
                            existingEntry.DriveFileId,
                            existingEntry.MimeType ?? "application/json"
                        );

                        if (existingMediaByGame.TryGetValue(game.Id, out var mediaEntries))
                        {
                            foreach (var mediaKvp in mediaEntries)
                            {
                                if (!candidateFiles.ContainsKey(mediaKvp.Key))
                                {
                                    candidateFiles[mediaKvp.Key] = new PlannedUpload(
                                        mediaKvp.Key,
                                        string.Empty,
                                        mediaKvp.Value.Sha256,
                                        mediaKvp.Value.SizeBytes,
                                        mediaKvp.Value.Category ?? "media",
                                        game.Id,
                                        mediaKvp.Value.DriveFileId,
                                        mediaKvp.Value.MimeType ?? "application/octet-stream"
                                    );
                                }
                            }
                        }
                    }
                    else
                    {
                        var (payload, mediaUploads) = await aggregator.BuildGamePayloadAsync(game, userDataDir).ConfigureAwait(false);
                        var jsonContent = DeterministicJsonSerializer.Serialize(payload);
                        var sha = Sha256Hasher.ComputeStringHash(jsonContent);
                        var size = Encoding.UTF8.GetByteCount(jsonContent);

                        gameStatCache[game.Id] = (game.Playtime, game.PlayCount, game.CoverImage ?? "", game.BackgroundImage ?? "", game.Icon ?? "");

                        candidateFiles[relPath] = new PlannedUpload(
                            relPath,
                            jsonContent,
                            sha,
                            size,
                            "game_metadata",
                            game.Id,
                            existingDriveFileId: null,
                            mimeType: "application/json"
                        );

                        foreach (var media in mediaUploads)
                        {
                            if (!candidateFiles.ContainsKey(media.RelativePath))
                            {
                                candidateFiles[media.RelativePath] = media;
                            }
                        }
                    }

                    scanned++;
                    // Ensure progress is reported immediately at step 0, 1, 2... and smoothly throughout
                    if (scanned <= 10 || scanned % Math.Max(1, total / 50) == 0 || scanned == total)
                    {
                        var scanReport = scanEstimator.Format(scanned, $"Checking game {scanned}/{total}: {game.Name}", "Step 1/3: Analyzing Library");
                        progress?.Report(new ExportProgressReport(scanReport, scanned, total));
                    }
                }

                ct.ThrowIfCancellationRequested();

                // Compute diff against previous index
                progress?.Report(new ExportProgressReport(
                    "Step 1/3: Comparing with Cloud Index...\r\nDiffing candidate files against previous sync index...",
                    total,
                    total,
                    indeterminate: true
                ));

                var diff = hashEngine.ComputeDiff(candidateFiles, currentIndex ?? new SyncIndex());

                if (!diff.HasChanges)
                {
                    Logger.Info("SyncIncrementalLibraryAsync: Entire library is up to date (0 changes).");
                    progress?.Report(new ExportProgressReport("Step 1/3: Complete • No changes detected. Library is up to date.", total, total));
                    return diff;
                }

                string storageName = storageProvider.ProviderName == "GoogleDrive" ? "Google Drive" : storageProvider.ProviderName;
                int pendingItems = diff.Added.Count + diff.Modified.Count + diff.Deleted.Count;
                progress?.Report(new ExportProgressReport(
                    $"Step 1/3: Complete • Connecting to {storageName}...\r\nPreparing cloud destination ({pendingItems} changes pending)...",
                    total,
                    total,
                    indeterminate: true
                ));

                await storageProvider.InitializeAsync(ct).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();

                using var semaphore = new SemaphoreSlim(concurrencyLimit);
                var allUploads = diff.Added.Concat(diff.Modified).ToList();

                var gameUploadsList = allUploads.Where(u => u.Category == "game_metadata").ToList();
                var mediaUploadsList = allUploads.Where(u => u.Category != "game_metadata" && u.Category != "manifest").ToList();

                int dirtyCount = gameUploadsList.Count;
                int mediaCount = mediaUploadsList.Count;
                var gameMap = games.ToDictionary(g => g.Id);
                int totalUploads = dirtyCount + mediaCount + 1;
                int uploadsDone = 0;
                var uploadEstimator = new ProgressEstimator(totalUploads);

                // Phase 2: Uploading dirty/new game payloads:
                int gamesDone = 0;
                var gameTasks = gameUploadsList.Select(async item =>
                {
                    await semaphore.WaitAsync(ct).ConfigureAwait(false);
                    try
                    {
                        ct.ThrowIfCancellationRequested();

                        var currentGames = Interlocked.Increment(ref gamesDone);
                        var overall = Interlocked.Increment(ref uploadsDone);
                        var gameName = (item.GameId.HasValue && gameMap.TryGetValue(item.GameId.Value, out var g))
                            ? g.Name
                            : item.RelativePath;

                        var reportText = uploadEstimator.Format(
                            overall,
                            $"Uploading game {currentGames}/{dirtyCount}: {gameName} ({overall}/{totalUploads})",
                            "Step 2/3: Uploading Payloads"
                        );

                        progress?.Report(new ExportProgressReport(
                            reportText,
                            overall,
                            totalUploads,
                            indeterminate: false
                        ));

                        using var ms = new MemoryStream(Encoding.UTF8.GetBytes(item.Content));
                        var fileId = await storageProvider.UploadFileAsync(
                            item.RelativePath,
                            item.MimeType,
                            ms,
                            item.ExistingDriveFileId,
                            null,
                            ct
                        ).ConfigureAwait(false);

                        lock (currentIndex.Entries)
                        {
                            currentIndex.Entries[item.RelativePath] = new IndexEntry
                            {
                                Sha256 = item.Sha256,
                                SizeBytes = item.SizeBytes,
                                ModifiedUtc = DateTime.UtcNow,
                                DriveFileId = fileId,
                                MimeType = item.MimeType,
                                Category = item.Category,
                                GameId = item.GameId
                            };
                        }
                    }
                    finally
                    {
                        semaphore.Release();
                    }
                });

                await Task.WhenAll(gameTasks).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();

                // Phase 3: Uploading media files:
                int mediaDone = 0;
                var mediaTasks = mediaUploadsList.Select(async item =>
                {
                    await semaphore.WaitAsync(ct).ConfigureAwait(false);
                    try
                    {
                        ct.ThrowIfCancellationRequested();

                        var currentMedia = Interlocked.Increment(ref mediaDone);
                        var overall = Interlocked.Increment(ref uploadsDone);
                        var fileName = Path.GetFileName(item.RelativePath);

                        var reportText = uploadEstimator.Format(
                            overall,
                            $"Uploading media {currentMedia}/{mediaCount}: {fileName} ({overall}/{totalUploads})",
                            "Step 2/3: Uploading Media"
                        );

                        progress?.Report(new ExportProgressReport(
                            reportText,
                            overall,
                            totalUploads,
                            indeterminate: false
                        ));

                        if (!string.IsNullOrEmpty(item.SourceFilePath) && File.Exists(item.SourceFilePath))
                        {
                            using var fs = new FileStream(item.SourceFilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                            var fileId = await storageProvider.UploadFileAsync(
                                item.RelativePath,
                                item.MimeType,
                                fs,
                                item.ExistingDriveFileId,
                                null,
                                ct
                            ).ConfigureAwait(false);

                            lock (currentIndex.Entries)
                            {
                                currentIndex.Entries[item.RelativePath] = new IndexEntry
                                {
                                    Sha256 = item.Sha256,
                                    SizeBytes = item.SizeBytes,
                                    ModifiedUtc = DateTime.UtcNow,
                                    DriveFileId = fileId,
                                    MimeType = item.MimeType,
                                    Category = item.Category,
                                    GameId = item.GameId
                                };
                            }
                        }
                    }
                    finally
                    {
                        semaphore.Release();
                    }
                });

                await Task.WhenAll(mediaTasks).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();

                // Upload manifest.json
                var manifestProgress = Interlocked.Increment(ref uploadsDone);
                var manifestReportText = uploadEstimator.Format(
                    manifestProgress,
                    $"Uploading manifest.json ({manifestProgress}/{totalUploads})",
                    "Step 2/3: Uploading Manifest"
                );
                progress?.Report(new ExportProgressReport(
                    manifestReportText,
                    manifestProgress,
                    totalUploads,
                    indeterminate: false
                ));
                var manifest = aggregator.BuildManifest(games, userDataDir);
                var manifestJson = DeterministicJsonSerializer.Serialize(manifest);
                var manifestSha = Sha256Hasher.ComputeStringHash(manifestJson);
                var manifestBytes = Encoding.UTF8.GetByteCount(manifestJson);

                string? existingManifestId = currentIndex.Entries.TryGetValue("manifest.json", out var mEntry)
                    ? mEntry.DriveFileId
                    : null;

                if (string.IsNullOrEmpty(existingManifestId))
                {
                    existingManifestId = await storageProvider.GetFileIdAsync("manifest.json", ct).ConfigureAwait(false);
                }

                using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(manifestJson)))
                {
                    var manifestFileId = await storageProvider.UploadFileAsync(
                        "manifest.json",
                        "application/json",
                        ms,
                        existingManifestId,
                        null,
                        ct
                    ).ConfigureAwait(false);

                    currentIndex.Entries["manifest.json"] = new IndexEntry
                    {
                        Sha256 = manifestSha,
                        SizeBytes = manifestBytes,
                        ModifiedUtc = DateTime.UtcNow,
                        DriveFileId = manifestFileId,
                        MimeType = "application/json",
                        Category = "manifest",
                        GameId = null
                    };
                }

                // Orphan Pruning (if enabled)
                if (settings.EnableOrphanPruning && diff.Deleted.Count > 0)
                {
                    var pruneEstimator = new ProgressEstimator(diff.Deleted.Count);
                    progress?.Report(new ExportProgressReport(pruneEstimator.Format(0, $"Pruning {diff.Deleted.Count} orphaned items...", "Step 2/3: Pruning Orphans"), 0, diff.Deleted.Count));
                    int pruned = 0;
                    foreach (var del in diff.Deleted)
                    {
                        ct.ThrowIfCancellationRequested();
                        try
                        {
                            await storageProvider.DeleteFileAsync(del.RelativePath, del.DriveFileId, ct).ConfigureAwait(false);
                            lock (currentIndex.Entries)
                            {
                                currentIndex.Entries.Remove(del.RelativePath);
                            }
                        }
                        catch (Exception ex)
                        {
                            Logger.Warn(ex, $"Failed pruning orphan file {del.RelativePath}");
                        }
                        pruned++;
                        var pruneReport = pruneEstimator.Format(pruned, $"Pruning orphan {pruned}/{diff.Deleted.Count}: {Path.GetFileName(del.RelativePath)}", "Step 2/3: Pruning Orphans");
                        progress?.Report(new ExportProgressReport(pruneReport, pruned, diff.Deleted.Count));
                    }
                }

                // Phase 4: Finalizing atomic index:
                string destName = storageProvider.ProviderName == "GoogleDrive" ? "Google Drive" : storageProvider.ProviderName;
                progress?.Report(new ExportProgressReport($"Step 3/3: Finalizing Sync • 100%\r\nCommitting sync_index.json to {destName}...", totalUploads, totalUploads, indeterminate: false));
                await CommitSyncIndexAsync(ct).ConfigureAwait(false);

                settings.LastSyncUtc = DateTime.UtcNow;
                progress?.Report(new ExportProgressReport("Step 3/3: Complete • 100%\r\nSync successfully completed!", totalUploads, totalUploads, indeterminate: false));
                return diff;
            }
            finally
            {
                syncLock.Release();
            }
        }

        public async Task ForceFullExportAsync(
            IProgress<ExportProgressReport>? progress = null,
            CancellationToken ct = default)
        {
            if (!storageProvider.IsAuthenticated)
            {
                var msg = storageProvider.ProviderName == "GoogleDrive"
                    ? "Google Drive authentication required. Please connect your Google account in Extension Settings or select Local Folder Sync."
                    : "Storage provider is not configured or authenticated.";
                Logger.Warn(msg);
                throw new InvalidOperationException(msg);
            }

            progress?.Report(new ExportProgressReport("Preparing full library re-export...", 0, 100, indeterminate: false));

            // Reset in-memory and on-disk index to force re-upload of all items
            await syncLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                currentIndex = new SyncIndex
                {
                    LibraryId = settings.LibraryId != Guid.Empty ? settings.LibraryId : Guid.NewGuid()
                };
                if (File.Exists(localIndexCachePath))
                {
                    File.Delete(localIndexCachePath);
                }
            }
            finally
            {
                syncLock.Release();
            }

            await SyncIncrementalLibraryAsync(progress, ct).ConfigureAwait(false);
        }

        private async Task CommitSyncIndexAsync(CancellationToken ct)
        {
            currentIndex.GeneratedAtUtc = DateTime.UtcNow;
            currentIndex.Version = "1.0.0";
            currentIndex.Generator = "playnite-exporter-plugin";
            currentIndex.ClientVersion = "1.0.0";
            currentIndex.TotalGames = currentIndex.Entries.Values.Count(e => e.Category == "game_metadata");
            currentIndex.TotalEntries = currentIndex.Entries.Count;
            currentIndex.TotalSizeBytes = currentIndex.Entries.Values.Sum(e => e.SizeBytes);

            var indexJson = DeterministicJsonSerializer.Serialize(currentIndex);

            string? existingIndexId = null;
            if (currentIndex.Entries.TryGetValue("sync_index.json", out var cachedEntry))
            {
                existingIndexId = cachedEntry.DriveFileId;
            }

            if (string.IsNullOrEmpty(existingIndexId))
            {
                existingIndexId = await storageProvider.GetFileIdAsync("sync_index.json", ct).ConfigureAwait(false);
            }

            using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(indexJson)))
            {
                var uploadedId = await storageProvider.UploadFileAsync(
                    "sync_index.json",
                    "application/json",
                    ms,
                    existingIndexId,
                    null,
                    ct
                ).ConfigureAwait(false);

                // Save locally
                File.WriteAllText(localIndexCachePath, indexJson, Encoding.UTF8);
            }
        }
    }
}
