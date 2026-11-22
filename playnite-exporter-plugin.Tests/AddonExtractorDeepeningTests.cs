using System;
using System.Collections.Generic;
using System.Data.SQLite;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Addons.Extractors;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class AddonExtractorDeepeningTests : IDisposable
    {
        private readonly string tempDir;
        private readonly string userDir;
        private readonly MockPlayniteEnvironment env;
        private readonly IPlayniteAPI mockApi;
        private readonly ExporterSettings settings;
        private readonly AddonExtractorRegistry addonRegistry;
        private readonly MediaProcessor mediaProcessor;
        private readonly MetadataAggregator aggregator;

        public AddonExtractorDeepeningTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "AddonDeepeningTests_" + Guid.NewGuid().ToString("N"));
            userDir = Path.Combine(tempDir, "UserData");
            Directory.CreateDirectory(userDir);

            env = new MockPlayniteEnvironment(userDir);
            mockApi = env.MockApi.Object;

            settings = new ExporterSettings
            {
                StorageType = SyncStorageType.LocalFolder,
                LocalFolderPath = Path.Combine(tempDir, "Sync")
            };
            Directory.CreateDirectory(settings.LocalFolderPath);

            addonRegistry = new AddonExtractorRegistry();
            mediaProcessor = new MediaProcessor(mockApi, settings);
            aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
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
                // Best effort
            }
        }

        [Fact]
        public async Task GenericExtractor_ExtractAsync_YieldsSelfContainedResultWithDataAndHash()
        {
            var game = new Game("Deepened Test Game") { Id = Guid.NewGuid() };
            var hltbExtractor = new HowLongToBeatExtractor();

            var hltbDir = Path.Combine(userDir, "ExtensionsData", hltbExtractor.PluginId.ToString(), "HowLongToBeat");
            Directory.CreateDirectory(hltbDir);
            var jsonPath = Path.Combine(hltbDir, $"{game.Id}.json");
            var jsonContent = @"{
                ""Items"": [
                    {
                        ""Id"": ""12345"",
                        ""Url"": ""https://howlongtobeat.com/game/12345"",
                        ""GameHltbData"": {
                            ""MainStoryClassic"": 36000,
                            ""MainExtraClassic"": 72000,
                            ""CompletionistClassic"": 108000
                        }
                    }
                ]
            }";
            File.WriteAllText(jsonPath, jsonContent);

            var result = await hltbExtractor.ExtractAsync(game, userDir);

            Assert.NotNull(result);
            Assert.Equal("how_long_to_beat", result.AddonKey);
            Assert.NotNull(result.Data);
            Assert.NotNull(result.StateHash);
            Assert.Empty(result.MediaUploads);
        }

        [Fact]
        public async Task PlayniteAchievementsExtractor_ExtractAsync_StagesSelfContainedMediaAndHash()
        {
            var game = new Game("Achievement Test Game")
            {
                Id = Guid.NewGuid(),
                Playtime = 3600,
                IsInstalled = true
            };

            var extractor = new PlayniteAchievementsExtractor();
            var pluginDir = Path.Combine(userDir, "ExtensionsData", extractor.PluginId.ToString());
            var iconCacheDir = Path.Combine(pluginDir, "icon_cache");
            Directory.CreateDirectory(iconCacheDir);

            var fakeIconPath = Path.Combine(iconCacheDir, "test_icon.jpg");
            File.WriteAllBytes(fakeIconPath, Encoding.UTF8.GetBytes("fake_jpg_content"));

            var dbPath = Path.Combine(pluginDir, "achievement_cache.db");
            SQLiteConnection.CreateFile(dbPath);

            var cs = new SQLiteConnectionStringBuilder { DataSource = dbPath, ReadOnly = false }.ToString();
            using (var conn = new SQLiteConnection(cs))
            {
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    CREATE TABLE Users (Id INTEGER PRIMARY KEY, ProviderKey TEXT, ExternalUserId TEXT, DisplayName TEXT, IsCurrentUser INTEGER);
                    CREATE TABLE Games (Id INTEGER PRIMARY KEY, ProviderKey TEXT, PlayniteGameId TEXT, GameName TEXT);
                    CREATE TABLE UserGameProgress (Id INTEGER PRIMARY KEY, UserId INTEGER, GameId INTEGER, AchievementsUnlocked INTEGER, TotalAchievements INTEGER, LastUpdatedUtc TEXT);
                    CREATE TABLE AchievementDefinitions (Id INTEGER PRIMARY KEY, GameId INTEGER, ApiName TEXT, DisplayName TEXT, Description TEXT, UnlockedIconPath TEXT, LockedIconPath TEXT, Points REAL, Category TEXT, Hidden INTEGER, GlobalPercentUnlocked REAL, ProgressMax REAL);
                    CREATE TABLE UserAchievements (Id INTEGER PRIMARY KEY, UserGameProgressId INTEGER, AchievementDefinitionId INTEGER, Unlocked INTEGER, UnlockTimeUtc TEXT, ProgressNum REAL, ProgressDenom REAL);

                    INSERT INTO Users VALUES (1, 'Custom', 'User1', 'TestUser', 1);
                    INSERT INTO Games VALUES (1, 'Custom', '" + game.Id.ToString() + @"', 'Achievement Test Game');
                    INSERT INTO UserGameProgress VALUES (1, 1, 1, 1, 1, '2026-01-01T00:00:00Z');
                    INSERT INTO AchievementDefinitions VALUES (1, 1, 'ACH_WIN', 'Winner', 'Win the match', 'icon_cache/test_icon.jpg', 'icon_cache/test_icon.jpg', 10.0, 'Default', 0, 85.5, 1.0);
                    INSERT INTO UserAchievements VALUES (1, 1, 1, 1, '2026-01-01T01:00:00Z', 1.0, 1.0);";
                cmd.ExecuteNonQuery();
            }

            var result = await extractor.ExtractAsync(game, userDir);

            Assert.NotNull(result);
            Assert.Equal("playnite_achievements", result.AddonKey);
            Assert.NotNull(result.Data);
            Assert.NotNull(result.StateHash);
            Assert.Single(result.MediaUploads);

            var upload = result.MediaUploads[0];
            Assert.Equal($"media/{game.Id}/achievements/ACH_WIN.jpg", upload.RelativePath);
            Assert.Equal(Path.GetFullPath(fakeIconPath), Path.GetFullPath(upload.SourceFilePath!));
            Assert.Equal("achievement_icon", upload.Category);
        }

        [Fact]
        public async Task SuccessStoryExtractor_ExtractAsync_StagesSelfContainedMediaAndHash()
        {
            var game = new Game("SuccessStory Test Game")
            {
                Id = Guid.NewGuid(),
                Playtime = 1800
            };

            var extractor = new SuccessStoryExtractor();
            var pluginDir = Path.Combine(userDir, "ExtensionsData", extractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(pluginDir);

            var cacheDir = Path.Combine(userDir, "cache", "SuccessStory");
            Directory.CreateDirectory(cacheDir);

            string iconUrl = "local_cache/trophy.png";
            string md5Hash;
            using (var md5 = MD5.Create())
            {
                var hashBytes = md5.ComputeHash(Encoding.UTF8.GetBytes(iconUrl));
                var sb = new StringBuilder(hashBytes.Length * 2);
                foreach (var b in hashBytes) sb.Append(b.ToString("x2"));
                md5Hash = sb.ToString();
            }

            var iconFile = Path.Combine(cacheDir, $"{md5Hash}.jpg");
            File.WriteAllBytes(iconFile, Encoding.UTF8.GetBytes("fake_success_story_icon"));

            var jsonPath = Path.Combine(pluginDir, $"{game.Id}.json");
            var jsonContent = @"{
                ""Items"": [
                    {
                        ""ApiName"": ""ACH_FIRST_STEP"",
                        ""Name"": ""First Step"",
                        ""Description"": ""Take first step"",
                        ""UrlUnlocked"": """ + iconUrl + @""",
                        ""DateUnlocked"": ""2026-01-01T00:00:00Z""
                    }
                ]
            }";
            File.WriteAllText(jsonPath, jsonContent);

            var result = await extractor.ExtractAsync(game, userDir);

            Assert.NotNull(result);
            Assert.Equal("success_story", result.AddonKey);
            Assert.NotNull(result.Data);
            Assert.NotNull(result.StateHash);
            Assert.Single(result.MediaUploads);

            var upload = result.MediaUploads[0];
            Assert.Equal($"media/{game.Id}/achievements/ACH_FIRST_STEP.jpg", upload.RelativePath);
            Assert.Equal(iconFile, upload.SourceFilePath);
        }

        [Fact]
        public async Task AddonRegistry_ExtractAllWithMediaAsync_AggregatesDataAndMediaUploads()
        {
            var game = new Game("Registry Test Game")
            {
                Id = Guid.NewGuid(),
                Playtime = 3600
            };

            // Seed HowLongToBeat
            var hltbExtractor = new HowLongToBeatExtractor();
            var hltbDir = Path.Combine(userDir, "ExtensionsData", hltbExtractor.PluginId.ToString(), "HowLongToBeat");
            Directory.CreateDirectory(hltbDir);
            File.WriteAllText(Path.Combine(hltbDir, $"{game.Id}.json"), @"{
                ""Items"": [{ ""Id"": ""1"", ""Url"": ""test"", ""GameHltbData"": { ""MainStoryClassic"": 100 } }]
            }");

            // Seed PlayniteAchievements
            var achExtractor = new PlayniteAchievementsExtractor();
            var pluginDir = Path.Combine(userDir, "ExtensionsData", achExtractor.PluginId.ToString());
            var iconCacheDir = Path.Combine(pluginDir, "icon_cache");
            Directory.CreateDirectory(iconCacheDir);
            var fakeIconPath = Path.Combine(iconCacheDir, "reg_icon.jpg");
            File.WriteAllBytes(fakeIconPath, Encoding.UTF8.GetBytes("reg_icon_bytes"));

            var dbPath = Path.Combine(pluginDir, "achievement_cache.db");
            SQLiteConnection.CreateFile(dbPath);
            var cs = new SQLiteConnectionStringBuilder { DataSource = dbPath, ReadOnly = false }.ToString();
            using (var conn = new SQLiteConnection(cs))
            {
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    CREATE TABLE Users (Id INTEGER PRIMARY KEY, ProviderKey TEXT, ExternalUserId TEXT, DisplayName TEXT, IsCurrentUser INTEGER);
                    CREATE TABLE Games (Id INTEGER PRIMARY KEY, ProviderKey TEXT, PlayniteGameId TEXT, GameName TEXT);
                    CREATE TABLE UserGameProgress (Id INTEGER PRIMARY KEY, UserId INTEGER, GameId INTEGER, AchievementsUnlocked INTEGER, TotalAchievements INTEGER, LastUpdatedUtc TEXT);
                    CREATE TABLE AchievementDefinitions (Id INTEGER PRIMARY KEY, GameId INTEGER, ApiName TEXT, DisplayName TEXT, Description TEXT, UnlockedIconPath TEXT, LockedIconPath TEXT, Points REAL, Category TEXT, Hidden INTEGER, GlobalPercentUnlocked REAL, ProgressMax REAL);
                    CREATE TABLE UserAchievements (Id INTEGER PRIMARY KEY, UserGameProgressId INTEGER, AchievementDefinitionId INTEGER, Unlocked INTEGER, UnlockTimeUtc TEXT, ProgressNum REAL, ProgressDenom REAL);

                    INSERT INTO Users VALUES (1, 'Custom', 'User1', 'TestUser', 1);
                    INSERT INTO Games VALUES (1, 'Custom', '" + game.Id.ToString() + @"', 'Registry Test Game');
                    INSERT INTO UserGameProgress VALUES (1, 1, 1, 1, 1, '2026-01-01T00:00:00Z');
                    INSERT INTO AchievementDefinitions VALUES (1, 1, 'ACH_REG', 'Reg Ach', 'Desc', 'icon_cache/reg_icon.jpg', 'icon_cache/reg_icon.jpg', 10.0, 'Default', 0, 50.0, 1.0);
                    INSERT INTO UserAchievements VALUES (1, 1, 1, 1, '2026-01-01T01:00:00Z', 1.0, 1.0);";
                cmd.ExecuteNonQuery();
            }

            var (addons, mediaUploads) = await addonRegistry.ExtractAllWithMediaAsync(game, userDir);

            Assert.True(addons.ContainsKey("how_long_to_beat"));
            Assert.True(addons.ContainsKey("playnite_achievements"));
            Assert.False(addons.ContainsKey("success_story")); // Suppressed
            Assert.Single(mediaUploads);
            Assert.Equal($"media/{game.Id}/achievements/ACH_REG.jpg", mediaUploads[0].RelativePath);
        }

        [Fact]
        public async Task MetadataAggregator_BuildGamePayloadAsync_PassesThroughAddonMediaUploads()
        {
            var game = new Game("Aggregator Passthrough Game")
            {
                Id = Guid.NewGuid(),
                Playtime = 3600
            };

            // Seed PlayniteAchievements with 1 achievement icon
            var achExtractor = new PlayniteAchievementsExtractor();
            var pluginDir = Path.Combine(userDir, "ExtensionsData", achExtractor.PluginId.ToString());
            var iconCacheDir = Path.Combine(pluginDir, "icon_cache");
            Directory.CreateDirectory(iconCacheDir);
            var fakeIconPath = Path.Combine(iconCacheDir, "agg_icon.jpg");
            File.WriteAllBytes(fakeIconPath, Encoding.UTF8.GetBytes("agg_icon_bytes"));

            var dbPath = Path.Combine(pluginDir, "achievement_cache.db");
            SQLiteConnection.CreateFile(dbPath);
            var cs = new SQLiteConnectionStringBuilder { DataSource = dbPath, ReadOnly = false }.ToString();
            using (var conn = new SQLiteConnection(cs))
            {
                conn.Open();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = @"
                    CREATE TABLE Users (Id INTEGER PRIMARY KEY, ProviderKey TEXT, ExternalUserId TEXT, DisplayName TEXT, IsCurrentUser INTEGER);
                    CREATE TABLE Games (Id INTEGER PRIMARY KEY, ProviderKey TEXT, PlayniteGameId TEXT, GameName TEXT);
                    CREATE TABLE UserGameProgress (Id INTEGER PRIMARY KEY, UserId INTEGER, GameId INTEGER, AchievementsUnlocked INTEGER, TotalAchievements INTEGER, LastUpdatedUtc TEXT);
                    CREATE TABLE AchievementDefinitions (Id INTEGER PRIMARY KEY, GameId INTEGER, ApiName TEXT, DisplayName TEXT, Description TEXT, UnlockedIconPath TEXT, LockedIconPath TEXT, Points REAL, Category TEXT, Hidden INTEGER, GlobalPercentUnlocked REAL, ProgressMax REAL);
                    CREATE TABLE UserAchievements (Id INTEGER PRIMARY KEY, UserGameProgressId INTEGER, AchievementDefinitionId INTEGER, Unlocked INTEGER, UnlockTimeUtc TEXT, ProgressNum REAL, ProgressDenom REAL);

                    INSERT INTO Users VALUES (1, 'Custom', 'User1', 'TestUser', 1);
                    INSERT INTO Games VALUES (1, 'Custom', '" + game.Id.ToString() + @"', 'Aggregator Passthrough Game');
                    INSERT INTO UserGameProgress VALUES (1, 1, 1, 1, 1, '2026-01-01T00:00:00Z');
                    INSERT INTO AchievementDefinitions VALUES (1, 1, 'ACH_AGG', 'Agg Ach', 'Desc', 'icon_cache/agg_icon.jpg', 'icon_cache/agg_icon.jpg', 10.0, 'Default', 0, 50.0, 1.0);
                    INSERT INTO UserAchievements VALUES (1, 1, 1, 1, '2026-01-01T01:00:00Z', 1.0, 1.0);";
                cmd.ExecuteNonQuery();
            }

            var (payload, mediaUploads) = await aggregator.BuildGamePayloadAsync(game, userDir);

            Assert.NotNull(payload);
            Assert.True(payload.Addons.ContainsKey("playnite_achievements"));
            Assert.Contains(mediaUploads, u => u.RelativePath == $"media/{game.Id}/achievements/ACH_AGG.jpg");
        }
    }
}
