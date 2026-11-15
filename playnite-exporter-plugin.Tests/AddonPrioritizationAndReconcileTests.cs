using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Addons.Extractors;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Storage;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class AddonPrioritizationAndReconcileTests : IDisposable
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

        public AddonPrioritizationAndReconcileTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlaynitePrioritizeTests_" + Guid.NewGuid().ToString("N"));
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
                MaxParallelUploads = 2
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
                userDir,
                addonRegistry
            );
        }

        public void Dispose()
        {
            try
            {
                System.Data.SQLite.SQLiteConnection.ClearAllPools();
                GC.Collect();
                GC.WaitForPendingFinalizers();
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, true);
                }
            }
            catch { }
        }

        private void SetupPlayniteAchievementsDb(Game game)
        {
            var achExtractor = new PlayniteAchievementsExtractor();
            var achDir = Path.Combine(userDir, "ExtensionsData", achExtractor.PluginId.ToString());
            Directory.CreateDirectory(achDir);
            var dbPath = Path.Combine(achDir, "achievement_cache.db");

            if (!File.Exists(dbPath))
            {
                System.Data.SQLite.SQLiteConnection.CreateFile(dbPath);
            }

            using (var conn = new System.Data.SQLite.SQLiteConnection($"Data Source={dbPath};"))
            {
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    CREATE TABLE IF NOT EXISTS Users (
                        Id INTEGER PRIMARY KEY AUTOINCREMENT,
                        ProviderKey TEXT NULL,
                        ExternalUserId TEXT NULL,
                        DisplayName TEXT NULL,
                        IsCurrentUser INTEGER NOT NULL DEFAULT 0
                    );
                    CREATE TABLE IF NOT EXISTS Games (
                        Id INTEGER PRIMARY KEY AUTOINCREMENT,
                        ProviderKey TEXT NULL,
                        PlayniteGameId TEXT NULL,
                        GameName TEXT NULL
                    );
                    CREATE TABLE IF NOT EXISTS UserGameProgress (
                        Id INTEGER PRIMARY KEY AUTOINCREMENT,
                        UserId INTEGER NOT NULL,
                        GameId INTEGER NOT NULL,
                        CacheKey TEXT NULL,
                        HasAchievements INTEGER NOT NULL DEFAULT 1,
                        AchievementsUnlocked INTEGER NOT NULL DEFAULT 0,
                        TotalAchievements INTEGER NOT NULL DEFAULT 0,
                        LastUpdatedUtc TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS AchievementDefinitions (
                        Id INTEGER PRIMARY KEY AUTOINCREMENT,
                        GameId INTEGER NOT NULL,
                        ApiName TEXT NOT NULL,
                        DisplayName TEXT NULL,
                        Description TEXT NULL,
                        UnlockedIconPath TEXT NULL,
                        LockedIconPath TEXT NULL,
                        Points INTEGER NULL,
                        Category TEXT NOT NULL DEFAULT 'Default',
                        Hidden INTEGER NOT NULL DEFAULT 0,
                        GlobalPercentUnlocked REAL NULL,
                        ProgressMax INTEGER NULL
                    );
                    CREATE TABLE IF NOT EXISTS UserAchievements (
                        Id INTEGER PRIMARY KEY AUTOINCREMENT,
                        UserGameProgressId INTEGER NOT NULL,
                        AchievementDefinitionId INTEGER NOT NULL,
                        Unlocked INTEGER NOT NULL DEFAULT 0,
                        UnlockTimeUtc TEXT NULL,
                        ProgressNum INTEGER NULL,
                        ProgressDenom INTEGER NULL
                    );
                ";
                cmd.ExecuteNonQuery();

                long nextGameId;
                using (var insertGame = conn.CreateCommand())
                {
                    insertGame.CommandText = "INSERT INTO Games (PlayniteGameId) VALUES (@id); SELECT last_insert_rowid();";
                    insertGame.Parameters.AddWithValue("@id", game.Id.ToString());
                    nextGameId = (long)insertGame.ExecuteScalar();
                }

                using (var insertProg = conn.CreateCommand())
                {
                    insertProg.CommandText = @"
                        INSERT OR IGNORE INTO Users (Id, IsCurrentUser) VALUES (1, 1);
                        INSERT INTO UserGameProgress (UserId, GameId, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                        VALUES (1, @gameId, 5, 10, '2026-10-24T12:00:00Z');
                        SELECT last_insert_rowid();
                    ";
                    insertProg.Parameters.AddWithValue("@gameId", nextGameId);
                    long progId = (long)insertProg.ExecuteScalar();

                    using var insertAch = conn.CreateCommand();
                    insertAch.CommandText = @"
                        INSERT INTO AchievementDefinitions (GameId, ApiName, DisplayName, Description, Points, Hidden, Category, GlobalPercentUnlocked)
                        VALUES (@gameId, 'ACH_1', 'Playnite First Win', 'Earned from PlayniteAchievements', 10, 0, 'Main', 50.0);
                        SELECT last_insert_rowid();
                    ";
                    insertAch.Parameters.AddWithValue("@gameId", nextGameId);
                    long defId = (long)insertAch.ExecuteScalar();

                    using var insertUserAch = conn.CreateCommand();
                    insertUserAch.CommandText = @"
                        INSERT INTO UserAchievements (UserGameProgressId, AchievementDefinitionId, Unlocked, UnlockTimeUtc)
                        VALUES (@progId, @defId, 1, '2026-10-24T12:00:00Z');
                    ";
                    insertUserAch.Parameters.AddWithValue("@progId", progId);
                    insertUserAch.Parameters.AddWithValue("@defId", defId);
                    insertUserAch.ExecuteNonQuery();
                }
            }
        }

        private void SetupSuccessStoryFile(Game game, string? title = null)
        {
            var ssExtractor = new SuccessStoryExtractor();
            var ssDir = Path.Combine(userDir, "ExtensionsData", ssExtractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(ssDir);
            var ssFile = Path.Combine(ssDir, $"{game.Id}.json");
            var itemTitle = title ?? "SuccessStory Old Win";
            File.WriteAllText(ssFile, $@"{{
                ""Items"": [
                    {{
                        ""Name"": ""{itemTitle}"",
                        ""DateUnlocked"": ""2026-05-01 10:00:00"",
                        ""GamerScore"": 50
                    }}
                ]
            }}");
        }

        [Fact]
        public async Task AddonRegistry_WhenBothPlayniteAchievementsAndSuccessStoryExist_ExportsPlayniteAchievementsAndOmitsSuccessStory()
        {
            var game = new Game("Hades") { Id = Guid.NewGuid() };
            SetupPlayniteAchievementsDb(game);
            SetupSuccessStoryFile(game);

            // Act
            var results = await addonRegistry.ExtractAllAsync(game, userDir);

            // Assert: PlayniteAchievements is present, SuccessStory is suppressed
            Assert.True(results.ContainsKey("playnite_achievements"), "playnite_achievements should be present");
            Assert.NotNull(results["playnite_achievements"]);
            Assert.False(results.ContainsKey("success_story"), "success_story should be omitted when playnite_achievements exists");
        }

        [Fact]
        public async Task AddonRegistry_WhenOnlySuccessStoryExists_ExportsSuccessStory()
        {
            var game = new Game("Celeste") { Id = Guid.NewGuid() };
            // Only set up SuccessStory, not PlayniteAchievements
            SetupSuccessStoryFile(game);

            // Act
            var results = await addonRegistry.ExtractAllAsync(game, userDir);

            // Assert
            Assert.False(results.ContainsKey("playnite_achievements"), "playnite_achievements should not be present");
            Assert.True(results.ContainsKey("success_story"), "success_story should be present when playnite_achievements does not exist");
            Assert.NotNull(results["success_story"]);
        }

        [Fact]
        public async Task ExportCoordinator_ExtractAllAddonDataAsync_MatchesRegistryPrioritization()
        {
            var game = new Game("Dead Cells") { Id = Guid.NewGuid() };
            SetupPlayniteAchievementsDb(game);
            SetupSuccessStoryFile(game);

            var results = await coordinator.ExtractAllAddonDataAsync(game, userDir);

            Assert.True(results.ContainsKey("playnite_achievements"));
            Assert.False(results.ContainsKey("success_story"));
        }

        [Fact]
        public async Task Aggregator_BuildGamePayload_OmitsSuccessStoryWhenPlayniteAchievementsPresent()
        {
            var game = new Game("Hollow Knight") { Id = Guid.NewGuid() };
            env.Games.Add(game);
            SetupPlayniteAchievementsDb(game);
            SetupSuccessStoryFile(game);

            var (payload, media) = await aggregator.BuildGamePayloadAsync(game, userDir);

            Assert.True(payload.Addons.ContainsKey("playnite_achievements"));
            Assert.False(payload.Addons.ContainsKey("success_story"));
        }

        [Fact]
        public void ComputeGameStateHash_WhenPlayniteAchievementsValid_OmitsSuccessStoryFromCombinedHash()
        {
            var game = new Game("Elden Ring") { Id = Guid.NewGuid() };
            SetupPlayniteAchievementsDb(game);
            SetupSuccessStoryFile(game, "Initial SuccessStory Title");

            var hash1 = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);

            // Modify SuccessStory JSON file on disk
            SetupSuccessStoryFile(game, "Modified SuccessStory Title That Alters Timestamp and Length");

            var hash2 = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);

            // Assert: Game state hash MUST be identical because SuccessStory is excluded when PlayniteAchievements is valid
            Assert.Equal(hash1, hash2);
        }

        [Fact]
        public void ComputeGameStateHash_WhenPlayniteAchievementsNotPresent_IncludesSuccessStoryInCombinedHash()
        {
            var game = new Game("Balatro") { Id = Guid.NewGuid() };
            // Only SuccessStory exists
            SetupSuccessStoryFile(game, "Initial SuccessStory Title");

            var hash1 = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);

            // Modify SuccessStory JSON file on disk (alter timestamp & size)
            System.Threading.Thread.Sleep(20);
            SetupSuccessStoryFile(game, "Completely different content to change file size and timestamp");

            var hash2 = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);

            // Assert: Because PlayniteAchievements does not exist, SuccessStory is included and altering it changes the hash
            Assert.NotEqual(hash1, hash2);
        }

        [Fact]
        public void ComputeDiff_WhenLoadingSyncIndexWithNullStateHashes_HealsStateHashOnMatchingEntries()
        {
            var previousIndex = new SyncIndex
            {
                ClientVersion = "1.0.0"
            };

            var gameId = Guid.NewGuid();
            var relPath = $"games/{gameId}.json";

            // Existing entry with null StateHash (e.g. from an older version of exporter)
            previousIndex.Entries[relPath] = new IndexEntry
            {
                Sha256 = "sha256_candidate_payload_abc",
                SizeBytes = 512,
                ModifiedUtc = DateTime.UtcNow.AddDays(-1),
                Category = "game_metadata",
                GameId = gameId,
                DriveFileId = "drive_file_id_xyz",
                StateHash = null
            };

            var candidateFiles = new Dictionary<string, PlannedUpload>
            {
                [relPath] = new PlannedUpload(
                    relPath,
                    "{}",
                    "sha256_candidate_payload_abc",
                    512,
                    "game_metadata",
                    gameId,
                    existingDriveFileId: null,
                    mimeType: "application/json",
                    sourceFilePath: null,
                    stateHash: "state_hash_calculated_123"
                )
            };

            // Act
            var diff = hashEngine.ComputeDiff(candidateFiles, previousIndex);

            // Assert
            Assert.False(diff.HasChanges, "HasChanges must be false when SHA matches");
            Assert.True(diff.IndexHealed, "IndexHealed must be true when null StateHash was backfilled");
            Assert.Empty(diff.Added);
            Assert.Empty(diff.Modified);
            Assert.Empty(diff.Deleted);
            Assert.Single(diff.Unchanged);

            // Verify backfill in previousIndex directly
            Assert.Equal("state_hash_calculated_123", previousIndex.Entries[relPath].StateHash);
            Assert.Equal("state_hash_calculated_123", diff.Unchanged[relPath].StateHash);
        }

        [Fact]
        public async Task SyncIncrementalLibraryAsync_AutoReconcilesNullStateHashes_AndCommitsHealedIndex()
        {
            await coordinator.InitializeAsync();

            var game = new Game("Tunic")
            {
                Id = Guid.NewGuid(),
                Playtime = 1200,
                Modified = DateTime.UtcNow.AddHours(-1)
            };
            env.Games.Add(game);

            // Generate the exact candidate payload sha so it's a content match
            var (payload, _) = await aggregator.BuildGamePayloadAsync(game, userDir);
            var json = DeterministicJsonSerializer.Serialize(payload);
            var sha = Sha256Hasher.ComputeStringHash(json);

            var relPath = $"games/{game.Id}.json";

            // Simulate legacy index entry with NULL StateHash
            coordinator.CurrentIndex.Entries[relPath] = new IndexEntry
            {
                Sha256 = sha,
                SizeBytes = System.Text.Encoding.UTF8.GetByteCount(json),
                ModifiedUtc = DateTime.UtcNow.AddDays(-2),
                Category = "game_metadata",
                GameId = game.Id,
                DriveFileId = "local_drive_1",
                StateHash = null
            };

            // Act: First incremental sync run
            var diff1 = await coordinator.SyncIncrementalLibraryAsync();

            // Assert diff1: No content changes (+0 / -0), but index was healed!
            Assert.False(diff1.HasChanges);
            Assert.True(diff1.IndexHealed);
            Assert.NotNull(coordinator.CurrentIndex.Entries[relPath].StateHash);

            // Verify sync_index.json was committed to storageProvider (localSyncDir)
            var committedIndexPath = Path.Combine(localSyncDir, "sync_index.json");
            Assert.True(File.Exists(committedIndexPath), "sync_index.json should be committed to storage provider");

            var committedJson = File.ReadAllText(committedIndexPath);
            var committedIndex = DeterministicJsonSerializer.Deserialize<SyncIndex>(committedJson);
            Assert.NotNull(committedIndex);
            Assert.NotNull(committedIndex.Entries[relPath].StateHash);
            Assert.Equal(coordinator.CurrentIndex.Entries[relPath].StateHash, committedIndex.Entries[relPath].StateHash);

            // Act: Second incremental sync run
            var diff2 = await coordinator.SyncIncrementalLibraryAsync();

            // Assert diff2: Up to date, 0 changes, no healing needed on second run
            Assert.False(diff2.HasChanges);
            Assert.False(diff2.IndexHealed);
        }
    }
}