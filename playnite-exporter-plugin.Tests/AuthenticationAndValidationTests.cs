using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Moq;
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
    public class AuthenticationAndValidationTests : IDisposable
    {
        private readonly string tempDir;
        private readonly string userDir;
        private readonly MockPlayniteEnvironment env;
        private readonly IPlayniteAPI mockApi;

        public AuthenticationAndValidationTests()
        {
            tempDir = Path.Combine(Path.GetTempPath(), "PlayniteAuthTests_" + Guid.NewGuid().ToString("N"));
            userDir = Path.Combine(tempDir, "UserData");
            Directory.CreateDirectory(userDir);

            env = new MockPlayniteEnvironment(userDir);
            mockApi = env.MockApi.Object;
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
        public async Task ExportCoordinator_ThrowsException_WhenStorageUnauthenticated_SyncIncrementalLibraryAsync()
        {
            var settings = new ExporterSettings
            {
                StorageType = SyncStorageType.GoogleDrive
            };

            var mockStorage = new Mock<ISyncStorageProvider>();
            mockStorage.Setup(s => s.ProviderName).Returns("GoogleDrive");
            mockStorage.Setup(s => s.IsAuthenticated).Returns(false);

            var addonRegistry = new AddonExtractorRegistry();
            var mediaProcessor = new MediaProcessor(mockApi, settings);
            var aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
            var hashEngine = new DeltaHashEngine();

            var coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                mockStorage.Object,
                userDir
            );

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.SyncIncrementalLibraryAsync());
            Assert.Contains("Google Drive authentication required", ex.Message);
        }

        [Fact]
        public async Task ExportCoordinator_ThrowsException_WhenStorageUnauthenticated_ForceFullExportAsync()
        {
            var settings = new ExporterSettings
            {
                StorageType = SyncStorageType.GoogleDrive
            };

            var mockStorage = new Mock<ISyncStorageProvider>();
            mockStorage.Setup(s => s.ProviderName).Returns("GoogleDrive");
            mockStorage.Setup(s => s.IsAuthenticated).Returns(false);

            var addonRegistry = new AddonExtractorRegistry();
            var mediaProcessor = new MediaProcessor(mockApi, settings);
            var aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
            var hashEngine = new DeltaHashEngine();

            var coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                mockStorage.Object,
                userDir
            );

            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.ForceFullExportAsync());
            Assert.Contains("Google Drive authentication required", ex.Message);
        }

        [Fact]
        public async Task ExportCoordinator_ThrowsException_WhenStorageUnauthenticated_SyncSingleGameAsync()
        {
            var settings = new ExporterSettings
            {
                StorageType = SyncStorageType.GoogleDrive
            };

            var mockStorage = new Mock<ISyncStorageProvider>();
            mockStorage.Setup(s => s.ProviderName).Returns("GoogleDrive");
            mockStorage.Setup(s => s.IsAuthenticated).Returns(false);

            var addonRegistry = new AddonExtractorRegistry();
            var mediaProcessor = new MediaProcessor(mockApi, settings);
            var aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
            var hashEngine = new DeltaHashEngine();

            var coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                mockStorage.Object,
                userDir
            );

            var dummyGame = new Game("Test Game") { Id = Guid.NewGuid() };
            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.SyncSingleGameAsync(dummyGame));
            Assert.Contains("Google Drive authentication required", ex.Message);
        }

        [Fact]
        public void GoogleAuthService_IsAuthenticated_ReturnsFalse_WhenCredentialsMissing()
        {
            var settings = new ExporterSettings
            {
                GoogleClientId = "",
                GoogleClientSecret = ""
            };

            var auth = new GoogleAuthService(settings, userDir);
            Assert.False(auth.IsAuthenticated);
        }

        [Fact]
        public void GoogleAuthService_IsAuthenticated_ReturnsFalse_WhenNoToken()
        {
            var settings = new ExporterSettings
            {
                GoogleClientId = "valid_client_id.apps.googleusercontent.com",
                GoogleClientSecret = "valid_secret"
            };

            var auth = new GoogleAuthService(settings, userDir);
            Assert.False(auth.IsAuthenticated);
        }

        [Fact]
        public async Task GoogleDriveSyncProvider_InitializeAsync_Throws_WhenUnauthenticated()
        {
            var settings = new ExporterSettings
            {
                GoogleClientId = "",
                GoogleClientSecret = ""
            };

            var auth = new GoogleAuthService(settings, userDir);
            var provider = new GoogleDriveSyncProvider(auth, settings);

            Assert.False(provider.IsAuthenticated);
            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => provider.InitializeAsync());
            Assert.Contains("Google Drive authentication required", ex.Message);
        }

        [Fact]
        public void LocalFolderSyncProvider_IsAuthenticated_ReturnsTrue_ForValidRoot()
        {
            var validPath = Path.Combine(tempDir, "LocalFolder");
            Directory.CreateDirectory(validPath);
            var provider = new LocalFolderSyncProvider(validPath);
            Assert.True(provider.IsAuthenticated);
        }

        [Fact]
        public void ExporterSettingsViewModel_UnauthenticatedState_DisplaysNotConnected()
        {
            var settings = new ExporterSettings
            {
                GoogleClientId = "",
                GoogleClientSecret = ""
            };
            var auth = new GoogleAuthService(settings, userDir);
            var vm = new ExporterSettingsViewModel(null!, auth, settings);

            Assert.False(vm.IsGoogleConnected);
            Assert.False(vm.IsGoogleDriveConnected);
            Assert.True(vm.IsNotGoogleConnected);
            Assert.Equal("Status: Not Connected", vm.GoogleAuthStatusText);
            Assert.Equal(System.Windows.Visibility.Collapsed, vm.ConnectedVisibility);
            Assert.Equal(System.Windows.Visibility.Visible, vm.NotConnectedVisibility);
        }

        [Fact]
        public async Task ExportCoordinator_SyncIncrementalLibraryAsync_ReportsPhasesAndSupportsCancellation()
        {
            var localSyncDir = Path.Combine(tempDir, "LocalSyncProgress");
            Directory.CreateDirectory(localSyncDir);

            var settings = new ExporterSettings
            {
                StorageType = SyncStorageType.LocalFolder,
                LocalFolderPath = localSyncDir
            };

            var storageProvider = new LocalFolderSyncProvider(localSyncDir);
            var addonRegistry = new AddonExtractorRegistry();
            var mediaProcessor = new MediaProcessor(mockApi, settings);
            var aggregator = new MetadataAggregator(mockApi, addonRegistry, mediaProcessor);
            var hashEngine = new DeltaHashEngine();

            var coordinator = new ExportCoordinator(
                mockApi,
                settings,
                aggregator,
                hashEngine,
                storageProvider,
                userDir
            );

            // Add dummy game
            var game = new Game("Hades") { Id = Guid.NewGuid() };
            env.Games.Add(game);

            var reports = new List<ExportProgressReport>();
            var progress = new Progress<ExportProgressReport>(r => reports.Add(r));

            var diff = await coordinator.SyncIncrementalLibraryAsync(progress);
            Assert.True(diff.Added.Count > 0);

            // Verify cancellation
            var cts = new System.Threading.CancellationTokenSource();
            cts.Cancel();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
                coordinator.SyncIncrementalLibraryAsync(progress: null, ct: cts.Token));
        }
    }
}
