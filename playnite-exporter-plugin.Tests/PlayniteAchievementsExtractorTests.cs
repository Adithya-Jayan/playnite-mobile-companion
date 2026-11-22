using System;
using System.Data.SQLite;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Addons.Extractors;
using PlayniteExporterPlugin.Tests.Helpers;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class PlayniteAchievementsExtractorTests : IDisposable
    {
        private readonly string tempDir;
        private readonly PlayniteAchievementsExtractor extractor;
        private readonly string pluginDataDir;
        private readonly string dbPath;

        public PlayniteAchievementsExtractorTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteAchTests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            extractor = new PlayniteAchievementsExtractor();
            pluginDataDir = Path.Combine(tempDir, "ExtensionsData", extractor.PluginId.ToString());
            Directory.CreateDirectory(pluginDataDir);
            dbPath = Path.Combine(pluginDataDir, "achievement_cache.db");
        }

        public void Dispose()
        {
            try
            {
                SQLiteConnection.ClearAllPools();
                GC.Collect();
                GC.WaitForPendingFinalizers();
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, true);
                }
            }
            catch
            {
                // Best-effort cleanup
            }
        }

        private void InitializeDatabase(Action<SQLiteConnection>? seedAction = null)
        {
            AchievementDbTestHelper.CreateAndInitializeDatabase(dbPath);

            if (seedAction != null)
            {
                var cs = new SQLiteConnectionStringBuilder
                {
                    DataSource = dbPath,
                    ReadOnly = false
                }.ToString();

                using var conn = new SQLiteConnection(cs);
                conn.Open();
                seedAction(conn);
            }
        }

        [Fact]
        public void Metadata_HasExpectedValues()
        {
            Assert.Equal("playnite_achievements", extractor.AddonKey);
            Assert.Equal("Playnite Achievements", extractor.DisplayName);
            Assert.Equal(Guid.Parse("e6aad2c9-6e06-4d8d-ac55-ac3b252b5f7b"), extractor.PluginId);
        }

        [Fact]
        public void IsDataAvailable_WhenDbExists_ReturnsTrue()
        {
            InitializeDatabase();
            Assert.True(extractor.IsDataAvailable(tempDir));
        }

        [Fact]
        public void IsDataAvailable_WhenDbMissing_ReturnsFalse()
        {
            Assert.False(extractor.IsDataAvailable(tempDir));
        }

        [Fact]
        public async Task ExtractDataAsync_WhenDbMissing_ReturnsNull()
        {
            var game = new Game("Missing Game") { Id = Guid.NewGuid() };
            var result = await extractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_WhenGameNotInDb_ReturnsNull()
        {
            InitializeDatabase();
            var game = new Game("Unrecorded Game") { Id = Guid.NewGuid() };
            var result = await extractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_WhenTotalAchievementsIsZero_ReturnsNull()
        {
            var gameId = Guid.NewGuid();
            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 1);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Zero Achievement Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 0, 0, 0, '2026-10-24T00:00:00Z');
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Zero Achievement Game") { Id = gameId };
            var result = await extractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_WhenDefinitionsEmpty_ReturnsNull()
        {
            var gameId = Guid.NewGuid();
            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 1);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Empty Defs Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 0, 2, '2026-10-24T00:00:00Z');
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Empty Defs Game") { Id = gameId };
            var result = await extractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_ValidAchievements_ExtractsPayloadAndIcons()
        {
            var gameId = Guid.NewGuid();
            var iconRelDir = Path.Combine("icon_cache", gameId.ToString(), "original");
            var iconFullDir = Path.Combine(pluginDataDir, iconRelDir);
            Directory.CreateDirectory(iconFullDir);
            var iconPath1 = Path.Combine(iconFullDir, "ACH_1.jpg");
            File.WriteAllText(iconPath1, "fake_image_bytes");

            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 1);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Great Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 1, 2, '2026-10-24T10:00:00Z');

                    INSERT INTO AchievementDefinitions (Id, GameId, ApiName, DisplayName, Description, UnlockedIconPath, LockedIconPath, Points, Category, Hidden, GlobalPercentUnlocked, ProgressMax)
                    VALUES 
                    (1, 1, 'ACH_1', 'First Win', 'Win the first match', @icon1Rel, @icon1Rel, 20, 'Campaign', 0, 75.5, NULL),
                    (2, 1, 'ACH_2', 'Secret Boss', 'Defeat the hidden dragon', 'icon_cache/locked.jpg', 'icon_cache/locked.jpg', 50, 'Bosses', 1, 10.2, 100);

                    INSERT INTO UserAchievements (Id, UserGameProgressId, AchievementDefinitionId, Unlocked, UnlockTimeUtc, ProgressNum, ProgressDenom)
                    VALUES 
                    (1, 1, 1, 1, '2026-06-01T12:34:56Z', NULL, NULL),
                    (2, 1, 2, 0, NULL, 45, 100);
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.Parameters.AddWithValue("@icon1Rel", Path.Combine(iconRelDir, "ACH_1.jpg"));
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Great Game") { Id = gameId };
            var result = await extractor.ExtractDataAsync(game, tempDir);

            Assert.NotNull(result);
            var obj = JObject.FromObject(result!);

            Assert.True(obj.Value<bool>("has_achievements"));
            Assert.Equal(2, obj.Value<int>("total_count"));
            Assert.Equal(1, obj.Value<int>("unlocked_count"));
            Assert.Equal(1, obj.Value<int>("locked_count"));
            Assert.Equal(50.0, obj.Value<double>("unlocked_percentage"));
            Assert.Equal(20.0, obj.Value<double>("gamerscore_current"));
            Assert.Equal(70.0, obj.Value<double>("gamerscore_total"));

            var items = obj["items"] as JArray;
            Assert.NotNull(items);
            Assert.Equal(2, items!.Count);

            var item1 = items[0] as JObject;
            Assert.NotNull(item1);
            Assert.Equal("ACH_1", item1!.Value<string>("api_name"));
            Assert.Equal("First Win", item1.Value<string>("name"));
            Assert.Equal("Win the first match", item1.Value<string>("description"));
            Assert.True(item1.Value<bool>("unlocked"));
            Assert.True(item1.Value<bool>("is_unlocked"));
            Assert.Equal(20.0, item1.Value<double>("gamerscore"));
            Assert.Equal(75.5, item1.Value<double>("percent"));
            Assert.Equal(75.5, item1.Value<double>("rarity_percentage"));
            Assert.False(item1.Value<bool>("is_hidden"));
            Assert.Equal("Campaign", item1.Value<string>("category"));
            Assert.Equal("2026-06-01T12:34:56.000Z", item1.Value<string>("date_unlocked_utc"));
            Assert.Equal(iconPath1, item1.Value<string>("local_icon_path"));

            var item2 = items[1] as JObject;
            Assert.NotNull(item2);
            Assert.Equal("ACH_2", item2!.Value<string>("api_name"));
            Assert.Equal("Secret Boss", item2.Value<string>("name"));
            Assert.False(item2.Value<bool>("unlocked"));
            Assert.False(item2.Value<bool>("is_unlocked"));
            Assert.Null(item2["date_unlocked_utc"]?.Value<string>());
            Assert.True(item2.Value<bool>("is_hidden"));
            Assert.Equal(10.2, item2.Value<double>("rarity_percentage"));

            var prog = item2["progression"] as JObject;
            Assert.NotNull(prog);
            Assert.Equal(45.0, prog!.Value<double>("value"));
            Assert.Equal(100.0, prog.Value<double>("max"));
        }

        [Fact]
        public void Registry_IncludesPlayniteAchievementsExtractor()
        {
            var registry = new AddonExtractorRegistry();
            Assert.Contains(registry.RegisteredExtractors, e => e is PlayniteAchievementsExtractor);
        }

        [Fact]
        public async Task SuccessStoryExtractor_WhenZeroAchievements_ReturnsNull()
        {
            var ssExtractor = new SuccessStoryExtractor();
            var ssDir = Path.Combine(tempDir, "ExtensionsData", ssExtractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(ssDir);

            var gameId = Guid.NewGuid();
            var game = new Game("Zero SS Game") { Id = gameId };

            var ssJson = @"{
                ""DateLastRefresh"": ""2026-10-18T00:00:00Z"",
                ""Items"": []
            }";
            File.WriteAllText(Path.Combine(ssDir, $"{gameId}.json"), ssJson);

            var result = await ssExtractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task SuccessStoryExtractor_WhenItemsNull_ReturnsNull()
        {
            var ssExtractor = new SuccessStoryExtractor();
            var ssDir = Path.Combine(tempDir, "ExtensionsData", ssExtractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(ssDir);

            var gameId = Guid.NewGuid();
            var game = new Game("No Items SS Game") { Id = gameId };

            var ssJson = @"{
                ""DateLastRefresh"": ""2026-10-18T00:00:00Z""
            }";
            File.WriteAllText(Path.Combine(ssDir, $"{gameId}.json"), ssJson);

            var result = await ssExtractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_WhenNoCurrentUser_ReturnsNull()
        {
            var gameId = Guid.NewGuid();
            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 0);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Game Without Current User');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 1, 2, '2026-10-24T10:00:00Z');
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Game Without Current User") { Id = gameId };
            var result = await extractor.ExtractDataAsync(game, tempDir);
            Assert.Null(result);
        }

        [Fact]
        public async Task ExtractDataAsync_CaseInsensitiveGameId_FindsGame()
        {
            var gameId = Guid.NewGuid();
            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 1);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Upper Lower Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 1, 1, '2026-10-24T10:00:00Z');

                    INSERT INTO AchievementDefinitions (Id, GameId, ApiName, DisplayName, Description, UnlockedIconPath, LockedIconPath, Points, Category, Hidden, GlobalPercentUnlocked, ProgressMax)
                    VALUES (1, 1, 'ACH_WIN', 'Win', 'Desc', NULL, NULL, 10, 'General', 0, 99.0, NULL);

                    INSERT INTO UserAchievements (Id, UserGameProgressId, AchievementDefinitionId, Unlocked, UnlockTimeUtc)
                    VALUES (1, 1, 1, 1, '2026-01-01T00:00:00Z');
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString().ToUpperInvariant());
                cmd.ExecuteNonQuery();
            });

            // Pass lowercase GUID in Game object
            var game = new Game("Upper Lower Game") { Id = Guid.Parse(gameId.ToString().ToLowerInvariant()) };
            var result = await extractor.ExtractDataAsync(game, tempDir);

            Assert.NotNull(result);
            var obj = JObject.FromObject(result!);
            Assert.Equal(1, obj.Value<int>("total_count"));
            Assert.Equal(1, obj.Value<int>("unlocked_count"));
        }

        [Fact]
        public async Task ExtractDataAsync_ApiNameWithInvalidFileNameChars_SanitizesAndExtractsWithoutArgumentException()
        {
            var gameId = Guid.NewGuid();
            var iconRelDir = Path.Combine("icon_cache", gameId.ToString(), "original");
            var iconFullDir = Path.Combine(pluginDataDir, iconRelDir);
            Directory.CreateDirectory(iconFullDir);

            // The sanitized name for "minecraft:story/root" should be "minecraftstoryroot"
            var sanitized1 = string.Concat("minecraft:story/root".Split(Path.GetInvalidFileNameChars()));
            var iconPath1 = Path.Combine(iconFullDir, $"{sanitized1}.jpg");
            File.WriteAllText(iconPath1, "fake_bytes");

            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Users (Id, ProviderKey, ExternalUserId, DisplayName, IsCurrentUser)
                    VALUES (1, 'Steam', '12345', 'Player', 1);

                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Invalid Chars Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 1, 2, '2026-10-24T10:00:00Z');

                    INSERT INTO AchievementDefinitions (Id, GameId, ApiName, DisplayName, Description, UnlockedIconPath, LockedIconPath, Points, Category, Hidden, GlobalPercentUnlocked, ProgressMax)
                    VALUES 
                    (1, 1, 'minecraft:story/root', 'Minecraft Root', 'Root advancement', NULL, NULL, 10, 'Story', 0, 95.0, NULL),
                    (2, 1, 'advancement/nether:fast_travel?id=1*', 'Fast Travel', 'Travel 7km', NULL, NULL, 30, 'Nether', 0, 5.0, NULL);

                    INSERT INTO UserAchievements (Id, UserGameProgressId, AchievementDefinitionId, Unlocked, UnlockTimeUtc, ProgressNum, ProgressDenom)
                    VALUES 
                    (1, 1, 1, 1, '2026-06-01T12:00:00Z', NULL, NULL),
                    (2, 1, 2, 0, NULL, NULL, NULL);
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Invalid Chars Game") { Id = gameId };
            var result = await extractor.ExtractDataAsync(game, tempDir);

            Assert.NotNull(result);
            var obj = JObject.FromObject(result!);
            var items = obj["items"] as JArray;
            Assert.NotNull(items);
            Assert.Equal(2, items!.Count);

            var item1 = items[0] as JObject;
            Assert.NotNull(item1);
            Assert.Equal("minecraft:story/root", item1!.Value<string>("api_name"));
            Assert.True(item1.Value<bool>("unlocked"));
            Assert.True(item1.Value<bool>("is_unlocked"));
            Assert.Equal(iconPath1, item1.Value<string>("local_icon_path"));

            var item2 = items[1] as JObject;
            Assert.NotNull(item2);
            Assert.Equal("advancement/nether:fast_travel?id=1*", item2!.Value<string>("api_name"));
            Assert.False(item2.Value<bool>("unlocked"));
            Assert.False(item2.Value<bool>("is_unlocked"));
            Assert.Null(item2.Value<string>("local_icon_path"));
        }

        [Fact]
        public void GetStateHash_WhenDbFileMissing_ReturnsNull()
        {
            var game = new Game("No DB Game") { Id = Guid.NewGuid() };
            var hash = extractor.GetStateHash(game, tempDir);
            Assert.Null(hash);
        }

        [Fact]
        public void GetStateHash_WhenGameNotInDb_ReturnsNull()
        {
            InitializeDatabase();
            var game = new Game("Missing Game") { Id = Guid.NewGuid() };
            var hash = extractor.GetStateHash(game, tempDir);
            Assert.Null(hash);
        }

        [Fact]
        public void GetStateHash_WhenGameFound_ReturnsFormattedGranularHash()
        {
            var gameId = Guid.NewGuid();
            var lastUpdated = "2026-10-24T12:00:00Z";
            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Tracked Game');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 7, 20, @lastUpdated);
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString());
                cmd.Parameters.AddWithValue("@lastUpdated", lastUpdated);
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Tracked Game") { Id = gameId };
            var hash = extractor.GetStateHash(game, tempDir);

            Assert.NotNull(hash);
            Assert.Equal($"7_20_{lastUpdated}", hash);
        }

        [Fact]
        public void GetStateHash_GranularIsolation_UpdatingGameB_DoesNotChangeGameAHash()
        {
            var gameAId = Guid.NewGuid();
            var gameBId = Guid.NewGuid();
            var timeA = "2026-10-24T01:00:00Z";
            var timeB1 = "2026-10-24T01:00:00Z";
            var timeB2 = "2026-10-24T02:00:00Z";

            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @gameA, 'Game A'),
                           (2, 'Steam', @gameB, 'Game B');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_a', 1, 5, 10, @timeA),
                           (2, 1, 2, 'game_b', 1, 2, 15, @timeB1);
                ";
                cmd.Parameters.AddWithValue("@gameA", gameAId.ToString());
                cmd.Parameters.AddWithValue("@gameB", gameBId.ToString());
                cmd.Parameters.AddWithValue("@timeA", timeA);
                cmd.Parameters.AddWithValue("@timeB1", timeB1);
                cmd.ExecuteNonQuery();
            });

            var gameA = new Game("Game A") { Id = gameAId };
            var gameB = new Game("Game B") { Id = gameBId };

            var hashA1 = extractor.GetStateHash(gameA, tempDir);
            var hashB1 = extractor.GetStateHash(gameB, tempDir);

            Assert.Equal($"5_10_{timeA}", hashA1);
            Assert.Equal($"2_15_{timeB1}", hashB1);

            // Now update Game B's progress in the SQLite database
            using (var conn = new SQLiteConnection(new SQLiteConnectionStringBuilder { DataSource = dbPath }.ToString()))
            {
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    UPDATE UserGameProgress
                    SET AchievementsUnlocked = 3, LastUpdatedUtc = @timeB2
                    WHERE GameId = 2;
                ";
                cmd.Parameters.AddWithValue("@timeB2", timeB2);
                cmd.ExecuteNonQuery();
            }

            var hashA2 = extractor.GetStateHash(gameA, tempDir);
            var hashB2 = extractor.GetStateHash(gameB, tempDir);

            // Game A must remain completely unaffected
            Assert.Equal(hashA1, hashA2);
            // Game B's hash must reflect the update
            Assert.NotEqual(hashB1, hashB2);
            Assert.Equal($"3_15_{timeB2}", hashB2);
        }

        [Fact]
        public void GetStateHash_CaseInsensitiveGameId_FindsGame()
        {
            var gameId = Guid.NewGuid();
            var time = "2026-10-24T05:00:00Z";

            InitializeDatabase(conn =>
            {
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    INSERT INTO Games (Id, ProviderKey, PlayniteGameId, GameName)
                    VALUES (1, 'Steam', @playniteId, 'Case Test');

                    INSERT INTO UserGameProgress (Id, UserId, GameId, CacheKey, HasAchievements, AchievementsUnlocked, TotalAchievements, LastUpdatedUtc)
                    VALUES (1, 1, 1, 'game_1', 1, 10, 10, @time);
                ";
                cmd.Parameters.AddWithValue("@playniteId", gameId.ToString().ToUpperInvariant());
                cmd.Parameters.AddWithValue("@time", time);
                cmd.ExecuteNonQuery();
            });

            var game = new Game("Case Test") { Id = Guid.Parse(gameId.ToString().ToLowerInvariant()) };
            var hash = extractor.GetStateHash(game, tempDir);

            Assert.Equal($"10_10_{time}", hash);
        }
    }
}
