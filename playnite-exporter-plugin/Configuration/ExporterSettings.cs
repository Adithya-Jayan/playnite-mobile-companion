using System;
using System.IO;

namespace PlayniteExporterPlugin.Configuration
{
    public enum SyncStorageType
    {
        GoogleDrive,
        LocalFolder
    }

    public class ExporterSettings
    {
        public SyncStorageType StorageType { get; set; } = SyncStorageType.LocalFolder;

        public string LocalFolderPath { get; set; } = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "PlayniteSync"
        );

        public string GoogleDriveFolderName { get; set; } = "PlayniteSync";

        public string GoogleDriveFolderId { get; set; } = string.Empty;

        public string GoogleClientId { get; set; } = string.Empty;

        public string GoogleClientSecret { get; set; } = string.Empty;

        public bool AutoSyncOnGameStopped { get; set; } = true;

        public bool AutoSyncOnLibraryUpdated { get; set; } = true;

        public bool AutoSyncOnStartup { get; set; } = false;

        public bool SyncCovers { get; set; } = true;

        public bool SyncBackgrounds { get; set; } = true;

        public bool SyncLogos { get; set; } = true;

        public bool SyncMicrotrailers { get; set; } = true;

        public bool SyncTrailers { get; set; } = false;

        public int MaxParallelUploads { get; set; } = 4;

        public bool EnableOrphanPruning { get; set; } = true;

        public Guid LibraryId { get; set; } = Guid.NewGuid();

        public DateTime? LastSyncUtc { get; set; }
    }
}
