using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace PlayniteExporterPlugin.Models
{
    public class SyncIndex
    {
        [JsonProperty("version")]
        public string Version { get; set; } = "1.0.0";

        [JsonProperty("generator")]
        public string Generator { get; set; } = "playnite-exporter-plugin";

        [JsonProperty("client_version")]
        public string ClientVersion { get; set; } = "1.0.0";

        [JsonProperty("generated_at_utc")]
        public DateTime GeneratedAtUtc { get; set; } = DateTime.UtcNow;

        [JsonProperty("library_id")]
        public Guid LibraryId { get; set; }

        [JsonProperty("total_games")]
        public int TotalGames { get; set; }

        [JsonProperty("total_entries")]
        public int TotalEntries { get; set; }

        [JsonProperty("total_size_bytes")]
        public long TotalSizeBytes { get; set; }

        [JsonProperty("entries")]
        public Dictionary<string, IndexEntry> Entries { get; set; } = new();
    }

    public class IndexEntry
    {
        [JsonProperty("sha256")]
        public string Sha256 { get; set; } = string.Empty;

        [JsonProperty("size_bytes")]
        public long SizeBytes { get; set; }

        [JsonProperty("modified_utc")]
        public DateTime ModifiedUtc { get; set; }

        [JsonProperty("drive_file_id")]
        public string DriveFileId { get; set; } = string.Empty;

        [JsonProperty("mime_type")]
        public string MimeType { get; set; } = "application/json";

        [JsonProperty("category")]
        public string Category { get; set; } = "game_metadata";

        [JsonProperty("game_id")]
        public Guid? GameId { get; set; }
    }

    public class SyncDiff
    {
        public List<PlannedUpload> Added { get; } = new();
        public List<PlannedUpload> Modified { get; } = new();
        public List<PlannedDeletion> Deleted { get; } = new();
        public Dictionary<string, IndexEntry> Unchanged { get; } = new();

        public bool HasChanges => Added.Count > 0 || Modified.Count > 0 || Deleted.Count > 0;
    }

    public class PlannedUpload
    {
        public string RelativePath { get; set; }
        public string Content { get; set; }
        public string? SourceFilePath { get; set; }
        public string Sha256 { get; set; }
        public long SizeBytes { get; set; }
        public string Category { get; set; }
        public Guid? GameId { get; set; }
        public string? ExistingDriveFileId { get; set; }
        public string MimeType { get; set; }

        public PlannedUpload(
            string relativePath,
            string content,
            string sha256,
            long sizeBytes,
            string category,
            Guid? gameId = null,
            string? existingDriveFileId = null,
            string mimeType = "application/json",
            string? sourceFilePath = null)
        {
            RelativePath = relativePath;
            Content = content;
            Sha256 = sha256;
            SizeBytes = sizeBytes;
            Category = category;
            GameId = gameId;
            ExistingDriveFileId = existingDriveFileId;
            MimeType = mimeType;
            SourceFilePath = sourceFilePath;
        }
    }

    public class PlannedDeletion
    {
        public string RelativePath { get; set; }
        public string DriveFileId { get; set; }
        public string Category { get; set; }

        public PlannedDeletion(string relativePath, string driveFileId, string category)
        {
            RelativePath = relativePath;
            DriveFileId = driveFileId;
            Category = category;
        }
    }
}
