using System;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Storage;
using PlayniteExporterPlugin.Tests.Mocks;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class MediaDeduplicationTests : IDisposable
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

        public MediaDeduplicationTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteMediaTests_" + Guid.NewGuid().ToString("N"));
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
                SyncCovers = true
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
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
            catch { }
        }

        [Fact]
        public async Task Media_ContentAddressableDeduplication_SharesSingleStorageEntry()
        {
            // Create a shared cover image on disk (valid JPEG image)
            var coverFilePath = Path.Combine(tempDir, "shared_boxart.jpg");
            using (var bmp = new System.Drawing.Bitmap(10, 10))
            {
                bmp.Save(coverFilePath, System.Drawing.Imaging.ImageFormat.Jpeg);
            }
            env.FileMap["shared_cover_key"] = coverFilePath;

            // Two distinct games referencing the same cover
            var g1 = new Game("Witcher 3 (Steam)") { Id = Guid.NewGuid(), CoverImage = "shared_cover_key" };
            var g2 = new Game("Witcher 3 (GOG)") { Id = Guid.NewGuid(), CoverImage = "shared_cover_key" };

            env.Games.Add(g1);
            env.Games.Add(g2);

            await coordinator.InitializeAsync();
            var diff = await coordinator.SyncIncrementalLibraryAsync();

            // Total added files: 2 games + 1 shared cover
            var coverUploads = diff.Added.FindAll(a => a.Category == "cover");
            Assert.Single(coverUploads); // Deduplicated in planned uploads!

            var index = coordinator.CurrentIndex;
            var expectedCoverPath = coverUploads[0].RelativePath;
            Assert.True(index.Entries.ContainsKey(expectedCoverPath));

            // Verify physical file exists once
            var physicalCoverPath = Path.Combine(localSyncDir, expectedCoverPath.Replace('/', Path.DirectorySeparatorChar));
            Assert.True(File.Exists(physicalCoverPath));
        }
    }
}
