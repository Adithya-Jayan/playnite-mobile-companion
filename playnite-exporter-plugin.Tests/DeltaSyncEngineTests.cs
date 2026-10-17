using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Storage;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class DeltaSyncEngineTests : IDisposable
    {
        private readonly string tempDir;
        private readonly string localSyncDir;
        private readonly string userDir;
        private readonly MockPlayniteEnvironment env;
        private readonly IPlayniteAPI mockApi;
        private readonly ExporterSettings settings;
        private readonly LocalFolderSyncProvider storageProvider;
        private readonly AddonExtractorRegistry addonRegistry;
        private readonly MediaProcessor mediaProcessor;
        private readonly MetadataAggregator aggregator;
        private readonly DeltaHashEngine hashEngine;
        private readonly ExportCoordinator coordinator;

        private readonly Xunit.Abstractions.ITestOutputHelper output;

        public DeltaSyncEngineTests(Xunit.Abstractions.ITestOutputHelper output)
        {
            this.output = output;
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteDeltaTests_" + Guid.NewGuid().ToString("N"));
            localSyncDir = Path.Combine(tempDir, "LocalSync");
            userDir = Path.Combine(tempDir, "UserData");

            Directory.CreateDirectory(localSyncDir);
            Directory.CreateDirectory(userDir);

            env = new MockPlayniteEnvironment(userDir);
            mockApi = env.MockApi.Object;

            settings = new ExporterSettings
            {
                StorageType = SyncStorageType.LocalFolder,
                LocalFolderPath = localSyncDir,
                EnableOrphanPruning = true,
                MaxParallelUploads = 4
            };

            storageProvider = new LocalFolderSyncProvider(localSyncDir);
            addonRegistry = new AddonExtractorRegistry();
            mediaProcessor = new MediaProcessor(mockApi, settings);
            aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
            hashEngine = new DeltaHashEngine();

            coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                storageProvider,
                userDir
            );
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, true);
                }
            }
            catch { }
        }

        [Fact]
        public async Task FullSync_InitialExport_UploadsAllGamesAndManifest()
        {
            // Arrange: Add 3 games
            var g1 = new Game("Witcher 3") { Id = Guid.NewGuid(), Playtime = 3600, PlayCount = 2 };
            var g2 = new Game("Cyberpunk 2077") { Id = Guid.NewGuid(), Playtime = 7200, PlayCount = 4 };
            var g3 = new Game("Hades") { Id = Guid.NewGuid(), Playtime = 1800, PlayCount = 1 };

            env.Games.Add(g1);
            env.Games.Add(g2);
            env.Games.Add(g3);

            await coordinator.InitializeAsync();

            // Act: Run initial sync
            var diff = await coordinator.SyncIncrementalLibraryAsync();

            // Assert
            Assert.Equal(3, diff.Added.Count);
            Assert.Empty(diff.Modified);
            Assert.Empty(diff.Deleted);

            // Verify files exist in storage
            Assert.True(File.Exists(Path.Combine(localSyncDir, "sync_index.json")));
            Assert.True(File.Exists(Path.Combine(localSyncDir, "manifest.json")));
            Assert.True(File.Exists(Path.Combine(localSyncDir, "games", $"{g1.Id}.json")));
            Assert.True(File.Exists(Path.Combine(localSyncDir, "games", $"{g2.Id}.json")));
            Assert.True(File.Exists(Path.Combine(localSyncDir, "games", $"{g3.Id}.json")));

            // Verify index content
            var indexJson = File.ReadAllText(Path.Combine(localSyncDir, "sync_index.json"));
            var index = DeterministicJsonSerializer.Deserialize<SyncIndex>(indexJson);
            Assert.NotNull(index);
            Assert.Equal(3, index!.TotalGames);
        }

        [Fact]
        public async Task IncrementalSync_UnchangedLibrary_PerformsStrictNoOp()
        {
            // Arrange: Add 2 games and run initial sync
            var g1 = new Game("Game One") { Id = Guid.NewGuid(), Playtime = 100 };
            var g2 = new Game("Game Two") { Id = Guid.NewGuid(), Playtime = 200 };
            env.Games.Add(g1);
            env.Games.Add(g2);

            await coordinator.InitializeAsync();
            var initialDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.Equal(2, initialDiff.Added.Count);

            // Record write timestamps of files
            var indexLastWrite = File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "sync_index.json"));
            var g1LastWrite = File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g1.Id}.json"));

            await Task.Delay(50); // slight delay to verify timestamps

            // Act: Run second sync with ZERO modifications
            var secondDiff = await coordinator.SyncIncrementalLibraryAsync();

            // Assert: Strict No-Op (0 Added, 0 Modified, 0 Deleted)
            Assert.False(secondDiff.HasChanges);
            Assert.Empty(secondDiff.Added);
            Assert.Empty(secondDiff.Modified);
            Assert.Empty(secondDiff.Deleted);
            Assert.Equal(2, secondDiff.Unchanged.Count);

            // Files must remain completely untouched
            Assert.Equal(g1LastWrite, File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g1.Id}.json")));
        }

        [Fact]
        public async Task SingleGameSync_OnlyUpdatesTargetGameAndIndex()
        {
            var g1 = new Game("Game A") { Id = Guid.NewGuid(), Playtime = 1000 };
            var g2 = new Game("Game B") { Id = Guid.NewGuid(), Playtime = 2000 };
            env.Games.Add(g1);
            env.Games.Add(g2);

            await coordinator.InitializeAsync();
            await coordinator.SyncIncrementalLibraryAsync();

            var g2LastWrite = File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g2.Id}.json"));
            var initialG1Payload = File.ReadAllText(Path.Combine(localSyncDir, "games", $"{g1.Id}.json"));

            await Task.Delay(50);

            g1.Playtime = 4600;
            g1.PlayCount = 3;
            g1.LastActivity = DateTime.UtcNow;

            var success = await coordinator.SyncSingleGameAsync(g1);
            Assert.True(success);

            var updatedG1Payload = File.ReadAllText(Path.Combine(localSyncDir, "games", $"{g1.Id}.json"));
            Assert.NotEqual(initialG1Payload, updatedG1Payload);
            Assert.Contains("\"playtime_seconds\": 4600", updatedG1Payload);

            Assert.Equal(g2LastWrite, File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g2.Id}.json")));

            var indexJson = File.ReadAllText(Path.Combine(localSyncDir, "sync_index.json"));
            var index = DeterministicJsonSerializer.Deserialize<SyncIndex>(indexJson);

            Assert.NotNull(index);
            Assert.True(index!.Entries.ContainsKey($"games/{g1.Id}.json"));
            Assert.Equal(Sha256Hasher.ComputeStringHash(updatedG1Payload), index.Entries[$"games/{g1.Id}.json"].Sha256);
        }

        [Fact]
        public async Task SingleGameSync_UnchangedGame_IsStrictNoOp()
        {
            // Arrange
            var g1 = new Game("Game A") { Id = Guid.NewGuid(), Playtime = 1000 };
            env.Games.Add(g1);

            await coordinator.InitializeAsync();
            await coordinator.SyncIncrementalLibraryAsync();

            var g1LastWrite = File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g1.Id}.json"));
            var indexLastWrite = File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "sync_index.json"));

            await Task.Delay(50);

            // Act: Call SyncSingleGameAsync without changing anything
            var success = await coordinator.SyncSingleGameAsync(g1);
            Assert.True(success);

            // Assert: Timestamps unmodified
            Assert.Equal(g1LastWrite, File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "games", $"{g1.Id}.json")));
            Assert.Equal(indexLastWrite, File.GetLastWriteTimeUtc(Path.Combine(localSyncDir, "sync_index.json")));
        }

        [Fact]
        public async Task OrphanPruning_DeletesRemovedGameFiles()
        {
            // Arrange
            var g1 = new Game("Keep Me") { Id = Guid.NewGuid() };
            var g2 = new Game("Delete Me") { Id = Guid.NewGuid() };
            env.Games.Add(g1);
            env.Games.Add(g2);

            await coordinator.InitializeAsync();
            await coordinator.SyncIncrementalLibraryAsync();

            Assert.True(File.Exists(Path.Combine(localSyncDir, "games", $"{g2.Id}.json")));

            // Act: Remove g2 from Playnite library and re-sync
            env.Games.Remove(g2);
            var diff = await coordinator.SyncIncrementalLibraryAsync();

            // Assert
            Assert.Single(diff.Deleted);
            Assert.Equal($"games/{g2.Id}.json", diff.Deleted[0].RelativePath);
            Assert.False(File.Exists(Path.Combine(localSyncDir, "games", $"{g2.Id}.json")));
            Assert.True(File.Exists(Path.Combine(localSyncDir, "games", $"{g1.Id}.json")));

            var index = coordinator.CurrentIndex;
            Assert.False(index.Entries.ContainsKey($"games/{g2.Id}.json"));
            Assert.Equal(1, index.TotalGames);
        }

        [Fact]
        public async Task ThreeCoreDeltaSyncInvariants_Initial_NoOp_SingleGameModified_EndToEnd()
        {
            // Setup 3 games, one with media
            var coverFilePath = Path.Combine(tempDir, "game1_cover.jpg");
            using (var bmp = new System.Drawing.Bitmap(10, 10))
            {
                bmp.Save(coverFilePath, System.Drawing.Imaging.ImageFormat.Jpeg);
            }
            env.FileMap["g1_cover"] = coverFilePath;

            var g1 = new Game("Game 1") { Id = Guid.NewGuid(), Playtime = 1000, CoverImage = "g1_cover" };
            var g2 = new Game("Game 2") { Id = Guid.NewGuid(), Playtime = 2000 };
            var g3 = new Game("Game 3") { Id = Guid.NewGuid(), Playtime = 3000 };
            env.Games.Add(g1);
            env.Games.Add(g2);
            env.Games.Add(g3);

            settings.SyncCovers = true;
            await coordinator.InitializeAsync();

            // -------------------------------------------------------------
            // INVARIANT 1: Initial Export -> 100% of games and media are indexed and written
            // -------------------------------------------------------------
            var initialDiff = await coordinator.SyncIncrementalLibraryAsync();

            Assert.Equal(4, initialDiff.Added.Count); // 3 games + 1 cover
            Assert.Empty(initialDiff.Modified);
            Assert.Empty(initialDiff.Deleted);

            var g1Path = Path.Combine(localSyncDir, "games", $"{g1.Id}.json");
            var g2Path = Path.Combine(localSyncDir, "games", $"{g2.Id}.json");
            var g3Path = Path.Combine(localSyncDir, "games", $"{g3.Id}.json");
            var indexPath = Path.Combine(localSyncDir, "sync_index.json");
            var manifestPath = Path.Combine(localSyncDir, "manifest.json");

            Assert.True(File.Exists(g1Path));
            Assert.True(File.Exists(g2Path));
            Assert.True(File.Exists(g3Path));
            Assert.True(File.Exists(indexPath));
            Assert.True(File.Exists(manifestPath));

            var coverEntry = initialDiff.Added.First(a => a.Category == "cover");
            var coverDiskPath = Path.Combine(localSyncDir, coverEntry.RelativePath.Replace('/', Path.DirectorySeparatorChar));
            Assert.True(File.Exists(coverDiskPath));

            var indexStage1 = coordinator.CurrentIndex;
            Assert.Equal(3, indexStage1.TotalGames);
            Assert.Equal(5, indexStage1.TotalEntries); // 3 games + 1 cover + 1 manifest

            // Record timestamps of all files after initial export
            var g1WriteTime1 = File.GetLastWriteTimeUtc(g1Path);
            var g2WriteTime1 = File.GetLastWriteTimeUtc(g2Path);
            var g3WriteTime1 = File.GetLastWriteTimeUtc(g3Path);
            var coverWriteTime1 = File.GetLastWriteTimeUtc(coverDiskPath);
            var indexWriteTime1 = File.GetLastWriteTimeUtc(indexPath);
            var manifestWriteTime1 = File.GetLastWriteTimeUtc(manifestPath);

            await Task.Delay(100);

            // -------------------------------------------------------------
            // INVARIANT 2: Second Export (No Changes) -> 0 files rewritten. Hash check yields 0 diff.
            // -------------------------------------------------------------
            var secondDiff = await coordinator.SyncIncrementalLibraryAsync();

            Assert.False(secondDiff.HasChanges);
            Assert.Empty(secondDiff.Added);
            Assert.Empty(secondDiff.Modified);
            Assert.Empty(secondDiff.Deleted);
            Assert.Equal(4, secondDiff.Unchanged.Count); // 3 games + 1 cover

            // Strict 0-write check: timestamps must match exactly
            Assert.Equal(g1WriteTime1, File.GetLastWriteTimeUtc(g1Path));
            Assert.Equal(g2WriteTime1, File.GetLastWriteTimeUtc(g2Path));
            Assert.Equal(g3WriteTime1, File.GetLastWriteTimeUtc(g3Path));
            Assert.Equal(coverWriteTime1, File.GetLastWriteTimeUtc(coverDiskPath));
            Assert.Equal(indexWriteTime1, File.GetLastWriteTimeUtc(indexPath));
            Assert.Equal(manifestWriteTime1, File.GetLastWriteTimeUtc(manifestPath));

            await Task.Delay(100);

            // -------------------------------------------------------------
            // INVARIANT 3: Third Export (Single Game Modified) -> Modify 1 game's playtime.
            // Verify ONLY that 1 game's JSON and sync_index.json (and manifest for library aggregate) are modified.
            // Unchanged games and media MUST HAVE ZERO WRITES.
            // -------------------------------------------------------------
            g2.Playtime = 5400;
            g2.PlayCount = 7;
            g2.LastActivity = DateTime.UtcNow;

            var thirdDiff = await coordinator.SyncIncrementalLibraryAsync();

            Assert.True(thirdDiff.HasChanges);
            Assert.Empty(thirdDiff.Added);
            Assert.Single(thirdDiff.Modified);
            Assert.Equal($"games/{g2.Id}.json", thirdDiff.Modified[0].RelativePath);
            Assert.Empty(thirdDiff.Deleted);

            // Unchanged games and media MUST HAVE ZERO WRITES (identical timestamps)
            Assert.Equal(g1WriteTime1, File.GetLastWriteTimeUtc(g1Path));
            Assert.Equal(g3WriteTime1, File.GetLastWriteTimeUtc(g3Path));
            Assert.Equal(coverWriteTime1, File.GetLastWriteTimeUtc(coverDiskPath));

            // Target game G2 was rewritten
            var g2WriteTime3 = File.GetLastWriteTimeUtc(g2Path);
            Assert.True(g2WriteTime3 > g2WriteTime1);

            // Target game G2 payload contains the updated playtime
            var g2PayloadUpdated = File.ReadAllText(g2Path);
            Assert.Contains("\"playtime_seconds\": 5400", g2PayloadUpdated);

            // sync_index was updated with the new hash for G2
            var indexJson3 = File.ReadAllText(indexPath);
            var indexStage3 = DeterministicJsonSerializer.Deserialize<SyncIndex>(indexJson3);
            Assert.NotNull(indexStage3);
            Assert.Equal(Sha256Hasher.ComputeStringHash(g2PayloadUpdated), indexStage3!.Entries[$"games/{g2.Id}.json"].Sha256);
        }
    }
}
