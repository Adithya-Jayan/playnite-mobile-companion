using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
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
    public class ProgressDeadlockAndFastScanTests : IDisposable
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

        public ProgressDeadlockAndFastScanTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "ProgressDeadlockTests_" + Guid.NewGuid().ToString("N"));
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
        public void SynchronousProgress_ReportsDirectlyOnCallingThread()
        {
            int callerThreadId = Thread.CurrentThread.ManagedThreadId;
            int reportThreadId = -1;
            string reportedText = string.Empty;

            var progress = new SynchronousProgress<ExportProgressReport>(report =>
            {
                reportThreadId = Thread.CurrentThread.ManagedThreadId;
                reportedText = report.Text;
            });

            progress.Report(new ExportProgressReport("Test Message", 5, 10));

            Assert.Equal(callerThreadId, reportThreadId);
            Assert.Equal("Test Message", reportedText);
        }

        [Fact]
        public async Task SyncIncrementalLibraryAsync_1429UnchangedGames_ScansInUnder2Seconds()
        {
            await coordinator.InitializeAsync();

            // Populate mock database with 1,429 games
            var nowUtc = DateTime.UtcNow.AddHours(-1);
            for (int i = 0; i < 1429; i++)
            {
                var id = Guid.NewGuid();
                var game = new Game($"Game #{i:D4}")
                {
                    Id = id,
                    Playtime = (ulong)(i * 10),
                    Modified = nowUtc
                };
                env.Games.Add(game);

                // Simulate pre-existing index entry so all 1,429 games are considered up-to-date
                coordinator.CurrentIndex.Entries[$"games/{id}.json"] = new IndexEntry
                {
                    Sha256 = $"mock_hash_{i:D4}",
                    SizeBytes = 256,
                    ModifiedUtc = DateTime.UtcNow,
                    Category = "game_metadata",
                    GameId = id
                };
            }

            var reports = new List<ExportProgressReport>();
            var progress = new SynchronousProgress<ExportProgressReport>(r =>
            {
                reports.Add(r);
            });

            var sw = Stopwatch.StartNew();
            var diff = await coordinator.SyncIncrementalLibraryAsync(progress);
            sw.Stop();

            // Verify performance: 1,429 games must finish in < 2 seconds
            Assert.True(sw.Elapsed.TotalSeconds < 2.0, $"Expected scan to take < 2.0s, but took {sw.Elapsed.TotalSeconds:N2}s");

            // Verify diff: Strict No-Op (0 changes)
            Assert.False(diff.HasChanges);
            Assert.Empty(diff.Added);
            Assert.Empty(diff.Modified);
            Assert.Empty(diff.Deleted);
            Assert.Equal(1429, diff.Unchanged.Count);

            // Verify required progress messages
            Assert.True(reports.Count > 0, "Expected progress reports to be generated");
            Assert.Contains(reports, r => r.Text.Contains("Checking") && r.CurrentProgressValue == 0);
            Assert.Contains(reports, r => r.Text == "No changes detected. Library is up to date.");
        }

        [Fact]
        public async Task SyncIncrementalLibraryAsync_ReportsPhasesImmediately_StartingAtStep0()
        {
            await coordinator.InitializeAsync();

            // Add 10 games
            for (int i = 0; i < 10; i++)
            {
                var g = new Game($"Game {i}") { Id = Guid.NewGuid(), Modified = DateTime.UtcNow.AddMinutes(-5) };
                env.Games.Add(g);
            }

            var reports = new List<ExportProgressReport>();
            var progress = new SynchronousProgress<ExportProgressReport>(r => reports.Add(r));

            var diff = await coordinator.SyncIncrementalLibraryAsync(progress);

            Assert.True(diff.HasChanges);
            Assert.Equal(10, diff.Added.Count);

            // Verify step 0 report happened first
            var firstReport = reports.First();
            Assert.Contains("Checking", firstReport.Text);
            Assert.Equal(0, firstReport.CurrentProgressValue);
            Assert.Equal(10, firstReport.ProgressMaxValue);
        }
    }
}
