using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
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
    public class Phase2FixesTests : IDisposable
    {
        private readonly string tempDir;

        public Phase2FixesTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlaynitePhase2Tests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
        }

        public void Dispose()
        {
            if (Directory.Exists(tempDir))
            {
                try { Directory.Delete(tempDir, true); } catch { }
            }
        }

        [Fact]
        public async Task SystemCheckerExtractor_EmptyStub_ReturnsHasRequirementsFalseAndNullSpecs()
        {
            // Arrange
            var extractor = new SystemCheckerExtractor();
            var extDataDir = Path.Combine(tempDir, "ExtensionsData", extractor.PluginId.ToString(), "SystemChecker");
            Directory.CreateDirectory(extDataDir);

            var gameId = Guid.NewGuid();
            var game = new Game("Dummy Game") { Id = gameId };

            // 231 games in desktop library have empty stub arrays
            var stubJson = @"{
                ""Items"": [
                    {
                        ""IsMinimum"": true,
                        ""Os"": [],
                        ""Cpu"": [],
                        ""Gpu"": [],
                        ""Ram"": 0.0,
                        ""RamUsage"": null,
                        ""Storage"": 0.0,
                        ""StorageUsage"": null
                    },
                    {
                        ""IsMinimum"": false,
                        ""Os"": [],
                        ""Cpu"": [],
                        ""Gpu"": [],
                        ""Ram"": 0.0,
                        ""RamUsage"": null,
                        ""Storage"": 0.0,
                        ""StorageUsage"": null
                    }
                ]
            }";

            File.WriteAllText(Path.Combine(extDataDir, $"{gameId}.json"), stubJson);

            // Act
            var result = await extractor.ExtractDataAsync(game, tempDir);

            // Assert
            Assert.NotNull(result);
            var data = JObject.FromObject(result!);
            Assert.False(data.Value<bool>("has_requirements"));
            Assert.Equal(JTokenType.Null, data["minimum"]?.Type ?? JTokenType.Null);
            Assert.Equal(JTokenType.Null, data["recommended"]?.Type ?? JTokenType.Null);
        }

        [Fact]
        public async Task SystemCheckerExtractor_ValidSpecs_ReturnsHasRequirementsTrue()
        {
            // Arrange
            var extractor = new SystemCheckerExtractor();
            var extDataDir = Path.Combine(tempDir, "ExtensionsData", extractor.PluginId.ToString(), "SystemChecker");
            Directory.CreateDirectory(extDataDir);

            var gameId = Guid.NewGuid();
            var game = new Game("Spec Game") { Id = gameId };

            var validJson = @"{
                ""Items"": [
                    {
                        ""IsMinimum"": true,
                        ""Os"": [""Windows 10 64-bit""],
                        ""Cpu"": [""Intel Core i5-8400""],
                        ""Gpu"": [""NVIDIA GeForce GTX 1060""],
                        ""Ram"": 8589934592.0,
                        ""RamUsage"": ""8 GB"",
                        ""Storage"": 53687091200.0,
                        ""StorageUsage"": ""50 GB""
                    }
                ]
            }";

            File.WriteAllText(Path.Combine(extDataDir, $"{gameId}.json"), validJson);

            // Act
            var result = await extractor.ExtractDataAsync(game, tempDir);

            // Assert
            Assert.NotNull(result);
            var data = JObject.FromObject(result!);
            Assert.True(data.Value<bool>("has_requirements"));
            Assert.NotNull(data["minimum"]);
            Assert.Equal(JTokenType.Null, data["recommended"]?.Type ?? JTokenType.Null);
        }

        [Fact]
        public async Task SuccessStoryExtractor_ExtractsSourcesLink_AndPreservesNoRarety()
        {
            // Arrange
            var extractor = new SuccessStoryExtractor();
            var extDataDir = Path.Combine(tempDir, "ExtensionsData", extractor.PluginId.ToString(), "SuccessStory");
            Directory.CreateDirectory(extDataDir);

            var gameId = Guid.NewGuid();
            var game = new Game("Achievement Game") { Id = gameId };

            var ssJson = @"{
                ""DateLastRefresh"": ""2026-10-18T00:00:00Z"",
                ""SourcesLink"": {
                    ""GameName"": ""Cyberpunk 2077"",
                    ""Url"": ""https://store.steampowered.com/app/1091500""
                },
                ""Items"": [
                    {
                        ""Name"": ""Untracked Rarity Achievement"",
                        ""ApiName"": ""ACH_UNTRACKED"",
                        ""Description"": ""Mystery"",
                        ""UrlUnlocked"": ""https://cdn.example.com/ach1.jpg"",
                        ""UrlLocked"": """",
                        ""DateUnlocked"": ""2026-05-01T12:00:00Z"",
                        ""Percent"": 0.0,
                        ""NoRarety"": true,
                        ""GamerScore"": 15.0
                    },
                    {
                        ""Name"": ""Standard Rarity Achievement"",
                        ""ApiName"": ""ACH_STANDARD"",
                        ""Description"": ""Beat Game"",
                        ""UrlUnlocked"": ""https://cdn.example.com/ach2.jpg"",
                        ""UrlLocked"": """",
                        ""DateUnlocked"": null,
                        ""Percent"": 12.34,
                        ""NoRarety"": false,
                        ""GamerScore"": 30.0
                    }
                ]
            }";

            File.WriteAllText(Path.Combine(extDataDir, $"{gameId}.json"), ssJson);

            // Act
            var result = await extractor.ExtractDataAsync(game, tempDir);

            // Assert
            Assert.NotNull(result);
            var data = JObject.FromObject(result!);
            Assert.True(data.Value<bool>("has_achievements"));
            Assert.Equal("https://store.steampowered.com/app/1091500", data.Value<string>("store_url"));
            Assert.Equal("https://store.steampowered.com/app/1091500", data.Value<string>("sources_link"));

            var items = data["items"] as JArray;
            Assert.NotNull(items);
            Assert.Equal(2, items!.Count);

            var item1 = items[0] as JObject;
            Assert.NotNull(item1);
            Assert.True(item1!.Value<bool>("no_rarity"));
            Assert.Equal(JTokenType.Null, item1["rarity_percentage"]?.Type ?? JTokenType.Null);
            Assert.Equal("https://cdn.example.com/ach1.jpg", item1.Value<string>("url_unlocked"));

            var item2 = items[1] as JObject;
            Assert.NotNull(item2);
            Assert.False(item2!.Value<bool>("no_rarity"));
            Assert.Equal(12.34, item2.Value<double>("rarity_percentage"));
        }

        [Theory]
        [InlineData("Uknown", "https://store.playstation.com/en-us/concept/123", "PlayStation Store")]
        [InlineData("Unknown", "https://www.xbox.com/en-us/games/store/halo/456", "Xbox Store")]
        [InlineData("Store", "https://store.steampowered.com/app/789", "Steam")]
        [InlineData(null, "https://store.epicgames.com/p/game", "Epic Games Store")]
        [InlineData("Official Site", "https://cyberpunk.net", "Official Site")]
        public void MetadataAggregator_SanitizeLinkName_CleansTyposAndResolvesDomains(string? rawName, string url, string expected)
        {
            var result = MetadataAggregator.SanitizeLinkName(rawName, url);
            Assert.Equal(expected, result);
        }

        [Fact]
        public void MetadataAggregator_ResolveSource_FallsBackThroughPluginIdPlatformAndDomain()
        {
            var env = new MockPlayniteEnvironment(tempDir);
            var mediaProcessor = new MediaProcessor(env.MockApi.Object, new ExporterSettings());
            var aggregator = new MetadataAggregator(env.MockApi.Object, new AddonExtractorRegistry(), mediaProcessor);

            // Case 1: Built-in Xbox PluginId fallback
            var xboxGame = new Game("Xbox Title")
            {
                SourceId = Guid.Empty,
                PluginId = Guid.Parse("7e4fbb5e-2ae3-48d4-8ba0-6b30e7a4e287")
            };
            var xboxSrc = aggregator.ResolveSource(xboxGame);
            Assert.NotNull(xboxSrc);
            Assert.Equal("Xbox", xboxSrc!.Name);

            // Case 2: Platform Name fallback (e.g. PlayStation 5)
            var psPlatform = new Platform("PlayStation 5") { Id = Guid.NewGuid() };
            env.MockDb.Object.Platforms.Add(psPlatform);

            var psGame = new Game("PS Title")
            {
                SourceId = Guid.Empty,
                PluginId = Guid.Empty,
                PlatformIds = new List<Guid> { psPlatform.Id }
            };
            var psSrc = aggregator.ResolveSource(psGame);
            Assert.NotNull(psSrc);
            Assert.Equal("PlayStation", psSrc!.Name);

            // Case 3: Link domain inference fallback
            var domainGame = new Game("Web Game")
            {
                SourceId = Guid.Empty,
                PluginId = Guid.Empty,
                Links = new System.Collections.ObjectModel.ObservableCollection<Link>
                {
                    new Link("Store", "https://store.steampowered.com/app/12345")
                }
            };
            var domainSrc = aggregator.ResolveSource(domainGame);
            Assert.NotNull(domainSrc);
            Assert.Equal("Steam", domainSrc!.Name);
        }

        [Fact]
        public async Task MetadataAggregator_DuplicateHider_DynamicTagAndGrouping()
        {
            var env = new MockPlayniteEnvironment(tempDir);
            var mediaProcessor = new MediaProcessor(env.MockApi.Object, new ExporterSettings());
            var aggregator = new MetadataAggregator(env.MockApi.Object, new AddonExtractorRegistry(), mediaProcessor);

            // Create dynamic [DH] Hidden tag with a random non-default GUID
            var customDhTagId = Guid.NewGuid();
            var dhTag = new Tag("[DH] Hidden") { Id = customDhTagId };
            env.MockDb.Object.Tags.Add(dhTag);

            var gameTitle = "The Witcher 3: Wild Hunt";

            // Primary copy (Steam): not hidden, not duplicate
            var primaryGame = new Game(gameTitle)
            {
                Id = Guid.NewGuid(),
                Hidden = false,
                TagIds = new List<Guid>()
            };

            // Secondary copy (GOG): hidden by DuplicateHider with dynamic tag
            var secondaryGame = new Game(gameTitle)
            {
                Id = Guid.NewGuid(),
                Hidden = true,
                TagIds = new List<Guid> { customDhTagId }
            };

            // User-hidden game (manually hidden without [DH] Hidden tag)
            var userHiddenGame = new Game("Old Unrelated Title")
            {
                Id = Guid.NewGuid(),
                Hidden = true,
                TagIds = new List<Guid>()
            };

            env.Games.Add(primaryGame);
            env.Games.Add(secondaryGame);
            env.Games.Add(userHiddenGame);

            // Act
            var (primaryPayload, _) = await aggregator.BuildGamePayloadAsync(primaryGame, tempDir);
            var (secondaryPayload, _) = await aggregator.BuildGamePayloadAsync(secondaryGame, tempDir);
            var (userHiddenPayload, _) = await aggregator.BuildGamePayloadAsync(userHiddenGame, tempDir);

            // Assert: Primary copy
            Assert.False(primaryPayload.Hidden);
            Assert.False(primaryPayload.IsDuplicate); // Primary copy is NOT a duplicate
            Assert.NotNull(primaryPayload.DuplicateGroupId);
            Assert.NotEmpty(primaryPayload.OtherCopies);

            // Assert: Secondary copy
            Assert.True(secondaryPayload.Hidden);
            Assert.True(secondaryPayload.IsDuplicate); // Secondary copy IS marked as duplicate
            Assert.NotNull(secondaryPayload.DuplicateGroupId);
            Assert.Equal(primaryPayload.DuplicateGroupId, secondaryPayload.DuplicateGroupId); // Grouped together!

            // Assert: User-hidden game
            Assert.True(userHiddenPayload.Hidden);
            Assert.False(userHiddenPayload.IsDuplicate); // Must NOT be falsely classified as duplicate
            Assert.Null(userHiddenPayload.DuplicateGroupId);
        }
    }
}
