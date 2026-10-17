using System;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class AddonFaultToleranceTests : IDisposable
    {
        private readonly string tempDir;
        private readonly string userDir;
        private readonly MockPlayniteEnvironment env;
        private readonly IPlayniteAPI mockApi;
        private readonly AddonExtractorRegistry registry;
        private readonly MediaProcessor mediaProcessor;
        private readonly MetadataAggregator aggregator;

        public AddonFaultToleranceTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteAddonTests_" + Guid.NewGuid().ToString("N"));
            userDir = Path.Combine(tempDir, "UserData");
            Directory.CreateDirectory(userDir);

            env = new MockPlayniteEnvironment(userDir);
            mockApi = env.MockApi.Object;

            registry = new AddonExtractorRegistry();
            mediaProcessor = new MediaProcessor(mockApi, new ExporterSettings());
            aggregator = new MetadataAggregator(mockApi, registry, mediaProcessor);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
            catch { }
        }

        [Fact]
        public async Task MissingAddonFolder_ReturnsNull_ExportProceedsCleanly()
        {
            var game = new Game("Unmodded Game") { Id = Guid.NewGuid() };

            var (payload, _) = await aggregator.BuildGamePayloadAsync(game, userDir);

            Assert.NotNull(payload);
            Assert.Equal("Unmodded Game", payload.Name);
            Assert.Empty(payload.Addons);
        }

        [Fact]
        public async Task CorruptedAddonJson_CatchesErrorInBoundary_ReturnsNullWithoutCrashing()
        {
            var game = new Game("Fault Tolerant Game") { Id = Guid.NewGuid() };

            // Create corrupted SuccessStory file
            var ssDir = Path.Combine(userDir, "ExtensionsData", "cebe6d32-8c46-4459-b993-5a5189d60788", "SuccessStory");
            Directory.CreateDirectory(ssDir);
            File.WriteAllText(Path.Combine(ssDir, $"{game.Id}.json"), "{ INVALID JSON CORRUPTED FILE !!! >>> <<");

            // Create corrupted HowLongToBeat file
            var hltbDir = Path.Combine(userDir, "ExtensionsData", "e08cd51f-9c9a-4ee3-a094-fde03b55492f", "HowLongToBeat");
            Directory.CreateDirectory(hltbDir);
            File.WriteAllText(Path.Combine(hltbDir, $"{game.Id}.json"), "NOT A JSON AT ALL");

            var (payload, _) = await aggregator.BuildGamePayloadAsync(game, userDir);

            Assert.NotNull(payload);
            Assert.Equal("Fault Tolerant Game", payload.Name);
            Assert.False(payload.Addons.ContainsKey("success_story"));
            Assert.False(payload.Addons.ContainsKey("how_long_to_beat"));
        }

        [Fact]
        public async Task ValidAddonData_ExtractsCorrectly()
        {
            var game = new Game("Populated Game") { Id = Guid.NewGuid() };

            var hltbDir = Path.Combine(userDir, "ExtensionsData", "e08cd51f-9c9a-4ee3-a094-fde03b55492f", "HowLongToBeat");
            Directory.CreateDirectory(hltbDir);
            var hltbJson = @"
            {
              ""Items"": [
                {
                  ""Id"": ""12345"",
                  ""Url"": ""https://howlongtobeat.com/game/12345"",
                  ""GameHltbData"": {
                    ""MainStoryClassic"": 36000,
                    ""MainExtraClassic"": 72000,
                    ""CompletionistClassic"": 108000,
                    ""SoloClassic"": 36000,
                    ""CoOpClassic"": 0,
                    ""VsClassic"": 0
                  }
                }
              ]
            }";
            File.WriteAllText(Path.Combine(hltbDir, $"{game.Id}.json"), hltbJson);

            var (payload, _) = await aggregator.BuildGamePayloadAsync(game, userDir);

            Assert.NotNull(payload);
            Assert.True(payload.Addons.ContainsKey("how_long_to_beat"));
            var hltb = Newtonsoft.Json.Linq.JObject.FromObject(payload.Addons["how_long_to_beat"]!);
            Assert.True(hltb.Value<bool>("has_data"));
            Assert.Equal(36000L, hltb.Value<long>("main_story_seconds"));
            Assert.Equal(72000L, hltb.Value<long>("main_extra_seconds"));
            Assert.Equal(108000L, hltb.Value<long>("completionist_seconds"));
        }

        [Fact]
        public async Task EndToEndExport_WithCorruptedAndMissingAddons_SucceedsCleanly()
        {
            var exportDir = Path.Combine(tempDir, "ExportOutput");
            Directory.CreateDirectory(exportDir);

            var storageProvider = new Storage.LocalFolderSyncProvider(exportDir);
            var settings = new ExporterSettings
            {
                StorageType = SyncStorageType.LocalFolder,
                LocalFolderPath = exportDir
            };
            var hashEngine = new DeltaHashEngine();
            var coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                storageProvider,
                userDir
            );

            // Game 1: Normal with no addon data
            var g1 = new Game("Vanilla Game") { Id = Guid.NewGuid() };

            // Game 2: Has corrupted SuccessStory JSON
            var g2 = new Game("Corrupted Addon Game") { Id = Guid.NewGuid() };
            var ssDir = Path.Combine(userDir, "ExtensionsData", "cebe6d32-8c46-4459-b993-5a5189d60788", "SuccessStory");
            Directory.CreateDirectory(ssDir);
            File.WriteAllText(Path.Combine(ssDir, $"{g2.Id}.json"), "{{{{CORRUPT JSON NOT PARSABLE}}");

            // Game 3: Has valid HowLongToBeat data
            var g3 = new Game("Valid Addon Game") { Id = Guid.NewGuid() };
            var hltbDir = Path.Combine(userDir, "ExtensionsData", "e08cd51f-9c9a-4ee3-a094-fde03b55492f", "HowLongToBeat");
            Directory.CreateDirectory(hltbDir);
            File.WriteAllText(Path.Combine(hltbDir, $"{g3.Id}.json"), @"{""Items"": [{""Id"": ""999"", ""Url"": ""http://hltb.com/999"", ""GameHltbData"": {""MainStoryClassic"": 5000}}]}");

            env.Games.Add(g1);
            env.Games.Add(g2);
            env.Games.Add(g3);

            await coordinator.InitializeAsync();
            var diff = await coordinator.SyncIncrementalLibraryAsync();

            // Export must succeed with all 3 games added
            Assert.Equal(3, diff.Added.Count);
            Assert.Empty(diff.Modified);

            // Verify physical files written to disk
            var g1File = Path.Combine(exportDir, "games", $"{g1.Id}.json");
            var g2File = Path.Combine(exportDir, "games", $"{g2.Id}.json");
            var g3File = Path.Combine(exportDir, "games", $"{g3.Id}.json");

            Assert.True(File.Exists(g1File));
            Assert.True(File.Exists(g2File));
            Assert.True(File.Exists(g3File));

            // Verify payload content of g2 (corrupted addon skipped without crashing)
            var g2Payload = DeterministicJsonSerializer.Deserialize<UnifiedGamePayload>(File.ReadAllText(g2File));
            Assert.NotNull(g2Payload);
            Assert.Equal("Corrupted Addon Game", g2Payload!.Name);
            Assert.False(g2Payload.Addons.ContainsKey("success_story"));

            // Verify payload content of g3 (valid addon retained)
            var g3Payload = DeterministicJsonSerializer.Deserialize<UnifiedGamePayload>(File.ReadAllText(g3File));
            Assert.NotNull(g3Payload);
            Assert.True(g3Payload!.Addons.ContainsKey("how_long_to_beat"));
        }
    }
}
