using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using Playnite.SDK;
using Playnite.SDK.Plugins;
using PlayniteExporterPlugin.Storage;

namespace PlayniteExporterPlugin.Configuration
{
    public class ExporterSettingsViewModel : System.Collections.Generic.ObservableObject, ISettings
    {
        private readonly PlayniteExporterPlugin plugin;
        private readonly GoogleAuthService authService;
        private readonly ExporterSettings editingClone = new();
        private ExporterSettings settings;

        public ExporterSettings Settings
        {
            get => settings;
            set => SetValue(ref settings, value);
        }

        public bool IsGoogleConnected => authService.IsAuthenticated;
        public bool IsGoogleDriveConnected => IsGoogleConnected;
        public bool IsNotGoogleConnected => !IsGoogleConnected;

        public string ConnectedAccountInfo => authService.GetConnectedAccountInfo();

        public string GoogleAuthStatusText => IsGoogleConnected
            ? $"Status: Connected ({ConnectedAccountInfo})"
            : "Status: Not Connected";

        public string GoogleDriveStatusText => GoogleAuthStatusText;

        public Visibility ConnectedVisibility => IsGoogleConnected ? Visibility.Visible : Visibility.Collapsed;
        public Visibility NotConnectedVisibility => IsGoogleConnected ? Visibility.Collapsed : Visibility.Visible;

        public RelayCommand ConnectGoogleDriveCommand { get; }
        public RelayCommand DisconnectGoogleDriveCommand { get; }
        public RelayCommand CopyMobilePairingPayloadCommand { get; }
        public RelayCommand SelectLocalFolderCommand { get; }
        public RelayCommand OpenGoogleGuideCommand { get; }

        public ExporterSettingsViewModel(PlayniteExporterPlugin plugin, GoogleAuthService authService, ExporterSettings settings)
        {
            this.plugin = plugin;
            this.authService = authService;
            this.settings = settings;

            ConnectGoogleDriveCommand = new RelayCommand(async () =>
            {
                if (string.IsNullOrWhiteSpace(Settings.GoogleClientId) || string.IsNullOrWhiteSpace(Settings.GoogleClientSecret))
                {
                    var result = plugin.PlayniteApi.Dialogs.ShowMessage(
                        "Google Drive API credentials are required to connect.\n\n" +
                        "1. Please enter your Google Cloud OAuth Client ID and Client Secret in the fields below.\n\n" +
                        "OR\n\n" +
                        "2. Select 'Google Drive Desktop / Local Folder Sync' above to sync automatically via the Google Drive desktop app with ZERO API setup!\n\n" +
                        "Would you like to open the Google Cloud Console credentials page now?",
                        "Google Drive Credentials Required",
                        System.Windows.MessageBoxButton.YesNo,
                        System.Windows.MessageBoxImage.Information
                    );

                    if (result == System.Windows.MessageBoxResult.Yes)
                    {
                        try
                        {
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://console.cloud.google.com/apis/credentials") { UseShellExecute = true });
                        }
                        catch { }
                    }
                    return;
                }

                try
                {
                    await authService.AuthorizeInteractiveAsync();
                    plugin.UpdateStorageProvider();
                    RefreshGoogleAuthState();
                    plugin.PlayniteApi.Dialogs.ShowMessage($"Successfully connected to Google Drive!\nAccount: {ConnectedAccountInfo}", "Google Drive Auth");
                }
                catch (Exception ex)
                {
                    RefreshGoogleAuthState();
                    plugin.PlayniteApi.Dialogs.ShowErrorMessage($"Google Drive authorization failed: {ex.Message}", "Auth Error");
                }
            });

            DisconnectGoogleDriveCommand = new RelayCommand(() =>
            {
                authService.Disconnect();
                plugin.UpdateStorageProvider();
                RefreshGoogleAuthState();
                plugin.PlayniteApi.Dialogs.ShowMessage("Disconnected from Google Drive.", "Google Drive Auth");
            });

            CopyMobilePairingPayloadCommand = new RelayCommand(() =>
            {
                var payload = authService.GetMobilePairingPayload();
                if (string.IsNullOrEmpty(payload))
                {
                    plugin.PlayniteApi.Dialogs.ShowErrorMessage(
                        "No active Google Drive credentials found. Please connect to Google Drive in Playnite first.",
                        "Mobile Pairing"
                    );
                    return;
                }

                try
                {
                    Clipboard.SetText(payload);
                    plugin.PlayniteApi.Dialogs.ShowMessage(
                        "Mobile Pairing Code copied to clipboard!\n\n" +
                        "How to link your phone:\n" +
                        "1. Open the Playnite Mobile Companion app on your phone.\n" +
                        "2. Go to Settings > Sync & Storage Settings.\n" +
                        "3. Tap 'Link via Playnite Desktop Pairing Code' and paste this code.\n\n" +
                        "The mobile app will automatically refresh its Google Drive token in the background with zero maintenance!",
                        "Mobile Pairing Code Ready",
                        System.Windows.MessageBoxButton.OK,
                        System.Windows.MessageBoxImage.Information
                    );
                }
                catch (Exception ex)
                {
                    plugin.PlayniteApi.Dialogs.ShowErrorMessage($"Failed to copy to clipboard: {ex.Message}", "Clipboard Error");
                }
            });

            SelectLocalFolderCommand = new RelayCommand(() =>
            {
                var selected = plugin.PlayniteApi.Dialogs.SelectFolder();
                if (!string.IsNullOrEmpty(selected))
                {
                    Settings.LocalFolderPath = selected;
                    OnPropertyChanged(nameof(Settings));
                }
            });

            OpenGoogleGuideCommand = new RelayCommand(() =>
            {
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://console.cloud.google.com/apis/credentials") { UseShellExecute = true });
                }
                catch (Exception ex)
                {
                    plugin.PlayniteApi.Dialogs.ShowErrorMessage($"Could not open browser: {ex.Message}", "Error");
                }
            });

            RefreshGoogleAuthState();
        }

        public void RefreshGoogleAuthState()
        {
            OnPropertyChanged(nameof(IsGoogleConnected));
            OnPropertyChanged(nameof(IsGoogleDriveConnected));
            OnPropertyChanged(nameof(IsNotGoogleConnected));
            OnPropertyChanged(nameof(ConnectedAccountInfo));
            OnPropertyChanged(nameof(GoogleAuthStatusText));
            OnPropertyChanged(nameof(GoogleDriveStatusText));
            OnPropertyChanged(nameof(ConnectedVisibility));
            OnPropertyChanged(nameof(NotConnectedVisibility));
        }

        public void BeginEdit()
        {
            CopySettings(Settings, editingClone);
            RefreshGoogleAuthState();
        }

        public void CancelEdit()
        {
            CopySettings(editingClone, Settings);
            RefreshGoogleAuthState();
        }

        public void EndEdit()
        {
            plugin.SavePluginSettings(Settings);
            plugin.UpdateStorageProvider();
        }

        public bool VerifySettings(out List<string> errors)
        {
            errors = new List<string>();

            if (Settings.StorageType == SyncStorageType.LocalFolder)
            {
                if (string.IsNullOrWhiteSpace(Settings.LocalFolderPath))
                {
                    errors.Add("Local Sync Folder path cannot be empty.");
                }
            }
            else if (Settings.StorageType == SyncStorageType.GoogleDrive)
            {
                if (string.IsNullOrWhiteSpace(Settings.GoogleClientId) || string.IsNullOrWhiteSpace(Settings.GoogleClientSecret))
                {
                    errors.Add("Google Drive requires a Client ID and Client Secret (or switch to 'Google Drive Desktop / Local Folder Sync').");
                }
            }

            if (Settings.MaxParallelUploads < 1 || Settings.MaxParallelUploads > 16)
            {
                errors.Add("Max parallel uploads must be between 1 and 16.");
            }

            return errors.Count == 0;
        }

        private static void CopySettings(ExporterSettings source, ExporterSettings target)
        {
            target.StorageType = source.StorageType;
            target.LocalFolderPath = source.LocalFolderPath;
            target.GoogleDriveFolderName = source.GoogleDriveFolderName;
            target.GoogleDriveFolderId = source.GoogleDriveFolderId;
            target.GoogleClientId = source.GoogleClientId;
            target.GoogleClientSecret = source.GoogleClientSecret;
            target.AutoSyncOnGameStopped = source.AutoSyncOnGameStopped;
            target.AutoSyncOnLibraryUpdated = source.AutoSyncOnLibraryUpdated;
            target.AutoSyncOnStartup = source.AutoSyncOnStartup;
            target.SyncCovers = source.SyncCovers;
            target.SyncBackgrounds = source.SyncBackgrounds;
            target.SyncLogos = source.SyncLogos;
            target.SyncMicrotrailers = source.SyncMicrotrailers;
            target.SyncTrailers = source.SyncTrailers;
            target.MaxParallelUploads = source.MaxParallelUploads;
            target.EnableOrphanPruning = source.EnableOrphanPruning;
            target.LibraryId = source.LibraryId;
            target.LastSyncUtc = source.LastSyncUtc;
        }
    }
}
