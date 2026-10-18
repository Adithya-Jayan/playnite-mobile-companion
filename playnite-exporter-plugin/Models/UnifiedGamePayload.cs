using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace PlayniteExporterPlugin.Models
{
    public class UnifiedGamePayload
    {
        [JsonProperty("schema_version")]
        public string SchemaVersion { get; set; } = "1.0.0";

        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("game_id")]
        public string GameId { get; set; } = string.Empty;

        [JsonProperty("plugin_id")]
        public Guid PluginId { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("sorting_name")]
        public string SortingName { get; set; } = string.Empty;

        [JsonProperty("description")]
        public string? Description { get; set; }

        [JsonProperty("notes")]
        public string? Notes { get; set; }

        [JsonProperty("playtime_seconds")]
        public long PlaytimeSeconds { get; set; }

        [JsonProperty("play_count")]
        public long PlayCount { get; set; }

        [JsonProperty("added_utc")]
        public DateTime? AddedUtc { get; set; }

        [JsonProperty("modified_utc")]
        public DateTime? ModifiedUtc { get; set; }

        [JsonProperty("last_activity_utc")]
        public DateTime? LastActivityUtc { get; set; }

        [JsonProperty("recent_activity_utc")]
        public DateTime? RecentActivityUtc { get; set; }

        [JsonProperty("release_date")]
        public string? ReleaseDate { get; set; }

        [JsonProperty("is_installed")]
        public bool IsInstalled { get; set; }

        [JsonProperty("install_directory")]
        public string? InstallDirectory { get; set; }

        [JsonProperty("install_size_bytes")]
        public long? InstallSizeBytes { get; set; }

        [JsonProperty("hidden")]
        public bool Hidden { get; set; }

        [JsonProperty("is_duplicate")]
        public bool IsDuplicate { get; set; }

        [JsonProperty("duplicate_group_id")]
        public Guid? DuplicateGroupId { get; set; }

        [JsonProperty("other_copies")]
        public List<DuplicateCopyPayload> OtherCopies { get; set; } = new();

        [JsonProperty("favorite")]
        public bool Favorite { get; set; }

        [JsonProperty("version")]
        public string? Version { get; set; }

        [JsonProperty("user_score")]
        public int? UserScore { get; set; }

        [JsonProperty("critic_score")]
        public int? CriticScore { get; set; }

        [JsonProperty("community_score")]
        public int? CommunityScore { get; set; }

        [JsonProperty("source")]
        public NamedEntity? Source { get; set; }

        [JsonProperty("completion_status")]
        public NamedEntity? CompletionStatus { get; set; }

        [JsonProperty("platforms")]
        public List<PlatformEntity> Platforms { get; set; } = new();

        [JsonProperty("genres")]
        public List<NamedEntity> Genres { get; set; } = new();

        [JsonProperty("developers")]
        public List<NamedEntity> Developers { get; set; } = new();

        [JsonProperty("publishers")]
        public List<NamedEntity> Publishers { get; set; } = new();

        [JsonProperty("categories")]
        public List<NamedEntity> Categories { get; set; } = new();

        [JsonProperty("tags")]
        public List<NamedEntity> Tags { get; set; } = new();

        [JsonProperty("features")]
        public List<NamedEntity> Features { get; set; } = new();

        [JsonProperty("series")]
        public List<NamedEntity> Series { get; set; } = new();

        [JsonProperty("age_ratings")]
        public List<NamedEntity> AgeRatings { get; set; } = new();

        [JsonProperty("regions")]
        public List<NamedEntity> Regions { get; set; } = new();

        [JsonProperty("links")]
        public List<LinkEntity> Links { get; set; } = new();

        [JsonProperty("media")]
        public GameMediaContainer Media { get; set; } = new();

        [JsonProperty("addons")]
        public Dictionary<string, object?> Addons { get; set; } = new();
    }

    public class NamedEntity
    {
        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;
    }

    public class PlatformEntity
    {
        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("spec_id")]
        public string? SpecId { get; set; }
    }

    public class LinkEntity
    {
        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("url")]
        public string Url { get; set; } = string.Empty;
    }

    public class DuplicateCopyPayload
    {
        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("game_id")]
        public string GameId { get; set; } = string.Empty;

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("source_name")]
        public string SourceName { get; set; } = string.Empty;

        [JsonProperty("is_installed")]
        public bool IsInstalled { get; set; }

        [JsonProperty("playtime_seconds")]
        public long PlaytimeSeconds { get; set; }

        [JsonProperty("install_directory")]
        public string? InstallDirectory { get; set; }

        [JsonProperty("hidden")]
        public bool Hidden { get; set; }
    }
}
