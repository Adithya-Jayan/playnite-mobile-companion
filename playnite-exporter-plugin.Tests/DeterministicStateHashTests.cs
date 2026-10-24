using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Addons.Extractors;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Storage;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class DeterministicStateHashTests : IDisposable
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

        public DeterministicStateHashTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteHashTests_" + Guid.NewGuid().ToString("N"));
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
                if (Directory.Exists(tempDir))
                {
                    Directory.Delete(tempDir, true);
                }
            }
            catch { }
        }

        [Fact]
        public void ComputeGameStateHash_IdenticalGame_ProducesExactSameHash()
        {
            var gameId = Guid.NewGuid();
            var platformId = Guid.NewGuid();
            var genreId = Guid.NewGuid();

            var game1 = new Game("Hades")
            {
                Id = gameId,
                SortingName = "Hades",
                Playtime = 7200,
                PlayCount = 10,
                UserScore = 95,
                CriticScore = 93,
                CommunityScore = 90,
                Favorite = true,
                Hidden = false,
                IsInstalled = true,
                InstallDirectory = "C:\\Games\\Hades",
                Notes = "Great roguelike",
                Description = "Defy the god of the dead",
                PlatformIds = new List<Guid> { platformId },
                GenreIds = new List<Guid> { genreId },
                CoverImage = "cover.jpg",
                BackgroundImage = "bg.jpg",
                Icon = "icon.ico",
                Links = new System.Collections.ObjectModel.ObservableCollection<Link>
                {
                    new Link("Store", "https://store.steampowered.com/app/1145360")
                }
            };

            var game2 = new Game("Hades")
            {
                Id = gameId,
                SortingName = "Hades",
                Playtime = 7200,
                PlayCount = 10,
                UserScore = 95,
                CriticScore = 93,
                CommunityScore = 90,
                Favorite = true,
                Hidden = false,
                IsInstalled = true,
                InstallDirectory = "C:\\Games\\Hades",
                Notes = "Great roguelike",
                Description = "Defy the god of the dead",
                PlatformIds = new List<Guid> { platformId },
                GenreIds = new List<Guid> { genreId },
                CoverImage = "cover.jpg",
                BackgroundImage = "bg.jpg",
                Icon = "icon.ico",
                Links = new System.Collections.ObjectModel.ObservableCollection<Link>
                {
                    new Link("Store", "https://store.steampowered.com/app/1145360")
                }
            };

            var hash1 = hashEngine.ComputeGameStateHash(game1, userDir, addonRegistry);
            var hash2 = hashEngine.ComputeGameStateHash(game2, userDir, addonRegistry);

            Assert.NotNull(hash1);
            Assert.NotEmpty(hash1);
            Assert.Equal(hash1, hash2);
        }

        [Fact]
        public async Task ChangingPlaytime_WithUnchangedModified_AltersStateHash_AndMarksDirty()
        {
            var fixedDate = new DateTime(2025, 1, 1, 12, 0, 0, DateTimeKind.Utc);
            var game = new Game("Celeste")
            {
                Id = Guid.NewGuid(),
                Playtime = 1200,
                PlayCount = 2,
                Modified = fixedDate
            };
            env.Games.Add(game);

            await coordinator.InitializeAsync();
            var initialDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.Single(initialDiff.Added);
            Assert.Empty(initialDiff.Modified);

            var initialHash = coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash;
            Assert.NotNull(initialHash);

            // Second sync with no changes should be a no-op
            var secondDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.False(secondDiff.HasChanges);
            Assert.Single(secondDiff.Unchanged);

            // Mutate playtime ONLY, keeping Modified timestamp identical
            game.Playtime = 3600;
            game.Modified = fixedDate;

            var newHash = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);
            Assert.NotEqual(initialHash, newHash);

            var thirdDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.True(thirdDiff.HasChanges);
            Assert.Single(thirdDiff.Modified);
            Assert.Equal($"games/{game.Id}.json", thirdDiff.Modified[0].RelativePath);
            Assert.Equal(newHash, coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash);
        }

        [Fact]
        public async Task ChangingCoverImage_WithUnchangedModified_AltersStateHash_AndMarksDirty()
        {
            var cover1Path = Path.Combine(userDir, "cover1.png");
            var cover2Path = Path.Combine(userDir, "cover2.png");
            File.WriteAllBytes(cover1Path, new byte[] { 1, 2, 3 });
            File.WriteAllBytes(cover2Path, new byte[] { 4, 5, 6 });
            env.FileMap["cover_v1.png"] = cover1Path;
            env.FileMap["cover_v2.png"] = cover2Path;

            var fixedDate = new DateTime(2025, 1, 1, 12, 0, 0, DateTimeKind.Utc);
            var game = new Game("Dead Cells")
            {
                Id = Guid.NewGuid(),
                Playtime = 2400,
                CoverImage = "cover_v1.png",
                Modified = fixedDate
            };
            env.Games.Add(game);

            await coordinator.InitializeAsync();
            var initialDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.NotEmpty(initialDiff.Added);

            var initialHash = coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash;
            Assert.NotNull(initialHash);

            // Mutate CoverImage ONLY, keeping Modified timestamp identical
            game.CoverImage = "cover_v2.png";
            game.Modified = fixedDate;

            var newHash = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);
            Assert.NotEqual(initialHash, newHash);

            var secondDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.True(secondDiff.HasChanges);
            Assert.Contains(secondDiff.Modified, m => m.RelativePath == $"games/{game.Id}.json");
            Assert.Equal(newHash, coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash);
        }

        [Fact]
        public async Task UpdatingAddonFile_AltersStateHash_AndMarksDirty()
        {
            var game = new Game("Hollow Knight")
            {
                Id = Guid.NewGuid(),
                Playtime = 5000,
                Modified = new DateTime(2025, 1, 1, 12, 0, 0, DateTimeKind.Utc)
            };
            env.Games.Add(game);

            // Create an initial SuccessStory json file for this game
            var ssDir = Path.Combine(userDir, "ExtensionsData", "cebe6d32-8c46-4459-b993-5a5189d60788", "SuccessStory");
            Directory.CreateDirectory(ssDir);
            var ssFile = Path.Combine(ssDir, $"{game.Id}.json");
            File.WriteAllText(ssFile, "{\"Items\":[{\"Name\":\"False Knight\",\"Unlocked\":true}]}");

            await coordinator.InitializeAsync();
            var initialDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.Single(initialDiff.Added);

            var initialHash = coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash;
            Assert.NotNull(initialHash);

            // Second sync with no file changes is no-op
            var secondDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.False(secondDiff.HasChanges);

            // Now update the addon file on disk
            await Task.Delay(20);
            File.WriteAllText(ssFile, "{\"Items\":[{\"Name\":\"False Knight\",\"Unlocked\":true},{\"Name\":\"Hornet\",\"Unlocked\":true}]}");
            File.SetLastWriteTimeUtc(ssFile, DateTime.UtcNow.AddMinutes(10));

            var newHash = hashEngine.ComputeGameStateHash(game, userDir, addonRegistry);
            Assert.NotEqual(initialHash, newHash);

            var thirdDiff = await coordinator.SyncIncrementalLibraryAsync();
            Assert.True(thirdDiff.HasChanges);
            Assert.Single(thirdDiff.Modified);
            Assert.Equal($"games/{game.Id}.json", thirdDiff.Modified[0].RelativePath);
            Assert.Equal(newHash, coordinator.CurrentIndex.Entries[$"games/{game.Id}.json"].StateHash);
        }

        [Fact]
        public void Extractors_GetStateHash_BehaviorWhenFileMissingOrPresent()
        {
            var game = new Game("Test Game")
            {
                Id = Guid.NewGuid(),
                GameId = "steam_12345"
            };

            var ssExtractor = new SuccessStoryExtractor();
            var hltbExtractor = new HowLongToBeatExtractor();
            var actExtractor = new GameActivityExtractor();
            var dlcExtractor = new CheckDlcExtractor();
            var sysExtractor = new SystemCheckerExtractor();
            var plyExtractor = new PlayerActivitiesExtractor();
            var revExtractor = new SteamReviewsExtractor();
            var scrExtractor = new SteamScreenshotsExtractor();
            var extraExtractor = new ExtraMetadataExtractor();

            // When files are missing, all return null
            Assert.Null(ssExtractor.GetStateHash(game, userDir));
            Assert.Null(hltbExtractor.GetStateHash(game, userDir));
            Assert.Null(actExtractor.GetStateHash(game, userDir));
            Assert.Null(dlcExtractor.GetStateHash(game, userDir));
            Assert.Null(sysExtractor.GetStateHash(game, userDir));
            Assert.Null(plyExtractor.GetStateHash(game, userDir));
            Assert.Null(revExtractor.GetStateHash(game, userDir));
            Assert.Null(scrExtractor.GetStateHash(game, userDir));
            Assert.Null(extraExtractor.GetStateHash(game, userDir));

            // When SuccessStory file is created
            var ssDir = Path.Combine(userDir, "ExtensionsData", ssExtractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(ssDir);
            var ssFile = Path.Combine(ssDir, $"{game.Id}.json");
            File.WriteAllText(ssFile, "{}");

            var hash = ssExtractor.GetStateHash(game, userDir);
            Assert.NotNull(hash);
            Assert.Contains("_", hash);
        }
    }
}
