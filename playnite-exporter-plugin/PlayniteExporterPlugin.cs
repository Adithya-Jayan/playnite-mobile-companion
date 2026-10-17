using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Controls;
using Playnite.SDK;
using Playnite.SDK.Events;
using Playnite.SDK.Models;
using Playnite.SDK.Plugins;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using PlayniteExporterPlugin.Services;
using PlayniteExporterPlugin.Storage;
using PlayniteExporterPlugin.Views;

namespace PlayniteExporterPlugin
{
    public class PlayniteExporterPlugin : GenericPlugin
    {
        private static readonly ILogger Logger = LogManager.GetLogger();

        public override Guid Id { get; } = Guid.Parse("d3b07384-d113-4c90-951b-10f88a91a92a");

        private readonly ExporterSettings settings;
        private readonly ExporterSettingsViewModel settingsViewModel;
        private readonly ExportCoordinator coordinator;
        private readonly GoogleAuthService authService;

        public PlayniteExporterPlugin(IPlayniteAPI api) : base(api)
        {
            Properties = new GenericPluginProperties
            {
                HasSettings = true
            };

            var pluginUserDataDir = GetPluginUserDataPath();
            settings = LoadPluginSettings<ExporterSettings>() ?? new ExporterSettings();
            authService = new GoogleAuthService(settings, pluginUserDataDir);
            settingsViewModel = new ExporterSettingsViewModel(this, authService, settings);

            // Configure initial storage provider based on settings
            ISyncStorageProvider storageProvider;
            if (settings.StorageType == SyncStorageType.LocalFolder)
            {
                storageProvider = new LocalFolderSyncProvider(settings.LocalFolderPath);
            }
            else
            {
                storageProvider = new GoogleDriveSyncProvider(authService, settings);
            }

            var addonRegistry = new AddonExtractorRegistry();
            var mediaProcessor = new MediaProcessor(api, settings);
            var aggregator = new MetadataAggregator(api, addonRegistry, mediaProcessor);
            var hashEngine = new DeltaHashEngine();

            coordinator = new ExportCoordinator(
                api,
                settings,
                aggregator,
                hashEngine,
                storageProvider,
                pluginUserDataDir
            );
        }

        public void UpdateStorageProvider()
        {
            ISyncStorageProvider storageProvider;
            if (settings.StorageType == SyncStorageType.LocalFolder)
            {
                storageProvider = new LocalFolderSyncProvider(settings.LocalFolderPath);
            }
            else
            {
                storageProvider = new GoogleDriveSyncProvider(authService, settings);
            }
            coordinator.SetStorageProvider(storageProvider);
        }

        private void ShowUnauthenticatedError()
        {
            string message;
            if (settings.StorageType == SyncStorageType.GoogleDrive)
            {
                message = "Google Drive authentication required. Please connect your Google account in Extension Settings or select Local Folder Sync.";
            }
            else
            {
                message = "Local sync folder is not configured or accessible. Please check Extension Settings.";
            }

            Logger.Warn(message);
            PlayniteApi.Dialogs.ShowErrorMessage(message, "Mobile Delta Sync");
            PlayniteApi.Notifications.Add(
                new NotificationMessage("mobile_sync_unauth", message, NotificationType.Error)
            );
        }

        public override void OnApplicationStarted(OnApplicationStartedEventArgs args)
        {
            Task.Run(async () =>
            {
                try
                {
                    await coordinator.InitializeAsync();
                    if (settings.AutoSyncOnStartup)
                    {
                        if (settings.LastSyncUtc == null)
                        {
                            Logger.Info("Skipping auto-sync on startup: library has never been exported yet. Initial manual export required.");
                            return;
                        }

                        if (!coordinator.StorageProvider.IsAuthenticated)
                        {
                            Logger.Warn("Skipping auto-sync on startup: storage provider is not authenticated.");
                            return;
                        }
                        Logger.Info("AutoSync on startup triggered. Starting incremental sync...");
                        await coordinator.SyncIncrementalLibraryAsync();
                    }
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Failed to initialize Mobile Delta Sync Exporter on application start.");
                }
            });
        }

        public override void OnGameStopped(OnGameStoppedEventArgs args)
        {
            if (!settings.AutoSyncOnGameStopped || args.Game == null)
            {
                return;
            }

            if (settings.LastSyncUtc == null)
            {
                Logger.Info("Skipping auto-sync on game stopped: initial export has not been completed yet.");
                return;
            }

            if (!coordinator.StorageProvider.IsAuthenticated)
            {
                Logger.Warn("Skipping auto-sync on game stopped: storage provider is not authenticated.");
                return;
            }

            var game = args.Game;
            Logger.Info($"Game stopped: '{game.Name}' ({game.Id}). Enqueuing instant atomic delta sync.");

            Task.Run(async () =>
            {
                try
                {
                    await coordinator.SyncSingleGameAsync(game);
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, $"Failed atomic delta sync for game '{game.Name}' ({game.Id}).");
                }
            });
        }

        public override void OnLibraryUpdated(OnLibraryUpdatedEventArgs args)
        {
            if (!settings.AutoSyncOnLibraryUpdated)
            {
                return;
            }

            if (settings.LastSyncUtc == null)
            {
                Logger.Info("Skipping auto-sync on library update: initial export has not been completed yet.");
                return;
            }

            if (!coordinator.StorageProvider.IsAuthenticated)
            {
                Logger.Warn("Skipping auto-sync on library updated: storage provider is not authenticated.");
                return;
            }

            Logger.Info("Playnite library updated. Enqueuing incremental delta sync.");

            Task.Run(async () =>
            {
                try
                {
                    await coordinator.SyncIncrementalLibraryAsync();
                }
                catch (Exception ex)
                {
                    Logger.Error(ex, "Failed incremental delta sync after library update.");
                }
            });
        }

        public override IEnumerable<MainMenuItem> GetMainMenuItems(GetMainMenuItemsArgs args)
        {
            return new List<MainMenuItem>
            {
                new MainMenuItem
                {
                    Description = "Sync Library Now (Incremental Delta)",
                    MenuSection = "@Mobile Delta Sync",
                    Action = _ =>
                    {
                        if (!coordinator.StorageProvider.IsAuthenticated)
                        {
                            ShowUnauthenticatedError();
                            return;
                        }

                        if (coordinator.IsSyncInProgress)
                        {
                            PlayniteApi.Notifications.Add(
                                new NotificationMessage("mobile_sync_busy", "A mobile library sync is already currently running. Please wait for it to complete.", NotificationType.Info)
                            );
                            PlayniteApi.Dialogs.ShowMessage("A mobile library sync is already in progress. Please wait for it to finish.", "Mobile Sync Busy");
                            return;
                        }

                        var options = new GlobalProgressOptions("Syncing Library to Mobile Cloud...", true)
                        {
                            IsIndeterminate = false
                        };

                        PlayniteApi.Dialogs.ActivateGlobalProgress(async (progressArgs) =>
                        {
                            progressArgs.ProgressMaxValue = 100;
                            progressArgs.CurrentProgressValue = 0;
                            progressArgs.Text = "Initializing library sync...";
                            progressArgs.IsIndeterminate = false;

                            var progress = new SynchronousProgress<ExportProgressReport>(report =>
                            {
                                if (progressArgs.CancelToken.IsCancellationRequested) return;

                                if (report.ProgressMaxValue > 0)
                                {
                                    progressArgs.ProgressMaxValue = report.ProgressMaxValue;
                                }
                                progressArgs.CurrentProgressValue = report.CurrentProgressValue;
                                if (!string.IsNullOrEmpty(report.Text))
                                {
                                    progressArgs.Text = report.Text;
                                }
                                progressArgs.IsIndeterminate = false;
                            });

                            try
                            {
                                var diff = await coordinator.SyncIncrementalLibraryAsync(progress, progressArgs.CancelToken);

                                if (!diff.HasChanges)
                                {
                                    PlayniteApi.Notifications.Add(
                                        new NotificationMessage("mobile_sync_done", "Mobile sync complete: No changes detected. Library is up to date.", NotificationType.Info)
                                    );
                                }
                                else
                                {
                                    PlayniteApi.Notifications.Add(
                                        new NotificationMessage("mobile_sync_done", $"Mobile sync completed! (+{diff.Added.Count}, ~{diff.Modified.Count}, -{diff.Deleted.Count})", NotificationType.Info)
                                    );
                                }
                            }
                            catch (OperationCanceledException)
                            {
                                Logger.Info("Incremental library sync cancelled by user.");
                                PlayniteApi.Notifications.Add(
                                    new NotificationMessage("mobile_sync_cancel", "Mobile sync cancelled by user.", NotificationType.Info)
                                );
                            }
                            catch (Exception ex)
                            {
                                Logger.Error(ex, "Manual sync failed.");
                                PlayniteApi.Notifications.Add(
                                    new NotificationMessage("mobile_sync_err", $"Mobile sync failed: {ex.Message}", NotificationType.Error)
                                );
                                PlayniteApi.Dialogs.ShowErrorMessage($"Mobile sync failed: {ex.Message}", "Sync Error");
                            }
                        }, options);
                    }
                },
                new MainMenuItem
                {
                    Description = "Force Full Re-Export & Upload",
                    MenuSection = "@Mobile Delta Sync",
                    Action = _ =>
                    {
                        if (!coordinator.StorageProvider.IsAuthenticated)
                        {
                            ShowUnauthenticatedError();
                            return;
                        }

                        if (coordinator.IsSyncInProgress)
                        {
                            PlayniteApi.Notifications.Add(
                                new NotificationMessage("mobile_sync_busy", "A mobile library sync is already currently running. Please wait for it to complete.", NotificationType.Info)
                            );
                            PlayniteApi.Dialogs.ShowMessage("A mobile library sync is already in progress. Please wait for it to finish.", "Mobile Sync Busy");
                            return;
                        }

                        var answer = PlayniteApi.Dialogs.ShowMessage(
                            "This will rebuild all metadata, re-hash all media, and re-upload the entire library snapshot. Proceed?",
                            "Force Full Export",
                            System.Windows.MessageBoxButton.YesNo
                        );

                        if (answer == System.Windows.MessageBoxResult.Yes)
                        {
                            var options = new GlobalProgressOptions("Exporting Library to Mobile Cloud...", true)
                            {
                                IsIndeterminate = false
                            };

                            PlayniteApi.Dialogs.ActivateGlobalProgress(async (progressArgs) =>
                            {
                                progressArgs.ProgressMaxValue = 100;
                                progressArgs.CurrentProgressValue = 0;
                                progressArgs.Text = "Preparing full library re-export...";
                                progressArgs.IsIndeterminate = false;

                                var progress = new SynchronousProgress<ExportProgressReport>(report =>
                                {
                                    if (progressArgs.CancelToken.IsCancellationRequested) return;

                                    if (report.ProgressMaxValue > 0)
                                    {
                                        progressArgs.ProgressMaxValue = report.ProgressMaxValue;
                                    }
                                    progressArgs.CurrentProgressValue = report.CurrentProgressValue;
                                    if (!string.IsNullOrEmpty(report.Text))
                                    {
                                        progressArgs.Text = report.Text;
                                    }
                                    progressArgs.IsIndeterminate = false;
                                });

                                try
                                {
                                    await coordinator.ForceFullExportAsync(progress, progressArgs.CancelToken);

                                    PlayniteApi.Notifications.Add(
                                        new NotificationMessage("mobile_sync_done", "Full library export completed successfully!", NotificationType.Info)
                                    );
                                }
                                catch (OperationCanceledException)
                                {
                                    Logger.Info("Full library export cancelled by user.");
                                    PlayniteApi.Notifications.Add(
                                        new NotificationMessage("mobile_sync_cancel", "Full library export cancelled by user.", NotificationType.Info)
                                    );
                                }
                                catch (Exception ex)
                                {
                                    Logger.Error(ex, "Force full export failed.");
                                    PlayniteApi.Notifications.Add(
                                        new NotificationMessage("mobile_sync_err", $"Full export failed: {ex.Message}", NotificationType.Error)
                                    );
                                    PlayniteApi.Dialogs.ShowErrorMessage($"Full export failed: {ex.Message}", "Export Error");
                                }
                            }, options);
                        }
                    }
                },
                new MainMenuItem
                {
                    Description = "📱 Copy Mobile Companion Pairing Code",
                    MenuSection = "@Mobile Delta Sync",
                    Action = _ =>
                    {
                        var payload = authService.GetMobilePairingPayload();
                        if (string.IsNullOrEmpty(payload))
                        {
                            PlayniteApi.Dialogs.ShowErrorMessage(
                                "No active Google Drive credentials found. Please connect to Google Drive in Add-on Settings first.",
                                "Mobile Pairing"
                            );
                            return;
                        }

                        try
                        {
                            System.Windows.Clipboard.SetText(payload);
                            PlayniteApi.Dialogs.ShowMessage(
                                "Mobile Pairing Code copied to clipboard!\n\n" +
                                "How to link your phone:\n" +
                                "1. Open Playnite Mobile Companion on your phone.\n" +
                                "2. Go to Settings > Sync & Storage Settings.\n" +
                                "3. Tap 'Link via Playnite Desktop Pairing Code' and paste this code.\n\n" +
                                "The mobile app will automatically maintain its own Google Drive access without any manual API keys!",
                                "Mobile Pairing Code Ready",
                                System.Windows.MessageBoxButton.OK,
                                System.Windows.MessageBoxImage.Information
                            );
                        }
                        catch (Exception ex)
                        {
                            PlayniteApi.Dialogs.ShowErrorMessage($"Failed to copy to clipboard: {ex.Message}", "Clipboard Error");
                        }
                    }
                }
            };
        }

        public override IEnumerable<GameMenuItem> GetGameMenuItems(GetGameMenuItemsArgs args)
        {
            if (args.Games == null || args.Games.Count == 0) yield break;

            yield return new GameMenuItem
            {
                Description = "Sync Selected Game(s) to Mobile Cloud",
                MenuSection = "@Mobile Delta Sync",
                Action = _ =>
                {
                    if (!coordinator.StorageProvider.IsAuthenticated)
                    {
                        ShowUnauthenticatedError();
                        return;
                    }

                    var selectedGames = new List<Game>(args.Games);
                    var options = new GlobalProgressOptions("Syncing Selected Games to Mobile Cloud...", true)
                    {
                        IsIndeterminate = false
                    };

                    PlayniteApi.Dialogs.ActivateGlobalProgress((progressArgs) =>
                    {
                        int total = selectedGames.Count;
                        progressArgs.ProgressMaxValue = total;
                        progressArgs.CurrentProgressValue = 0;

                        int synced = 0;
                        for (int i = 0; i < total; i++)
                        {
                            if (progressArgs.CancelToken.IsCancellationRequested) break;

                            var g = selectedGames[i];
                            progressArgs.CurrentProgressValue = i;
                            progressArgs.Text = $"Syncing game {i + 1}/{total}: {g.Name}...";

                            try
                            {
                                Task.Run(async () =>
                                {
                                    await coordinator.SyncSingleGameAsync(g, null, progressArgs.CancelToken).ConfigureAwait(false);
                                }).GetAwaiter().GetResult();
                                synced++;
                            }
                            catch (OperationCanceledException)
                            {
                                break;
                            }
                            catch (Exception ex)
                            {
                                Logger.Error(ex, $"Failed syncing game {g.Name}");
                            }
                        }

                        progressArgs.CurrentProgressValue = total;
                        PlayniteApi.Notifications.Add(
                            new NotificationMessage("mobile_game_sync", $"Synced {synced} of {total} selected game(s) to mobile cloud.", NotificationType.Info)
                        );
                    }, options);
                }
            };
        }

        public override ISettings GetSettings(bool firstRunView)
        {
            return settingsViewModel;
        }

        public override UserControl GetSettingsView(bool firstRunView)
        {
            return new SettingsView { DataContext = settingsViewModel };
        }
    }
}
