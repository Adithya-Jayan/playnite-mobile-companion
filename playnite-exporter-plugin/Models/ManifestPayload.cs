using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace PlayniteExporterPlugin.Models
{
    public class ManifestPayload
    {
        [JsonProperty("version")]
        public string Version { get; set; } = "1.0.0";

        [JsonProperty("generated_at_utc")]
        public DateTime GeneratedAtUtc { get; set; } = DateTime.UtcNow;

        [JsonProperty("library_summary")]
        public LibrarySummary LibrarySummary { get; set; } = new();

        [JsonProperty("sources")]
        public List<SourceItem> Sources { get; set; } = new();

        [JsonProperty("completion_statuses")]
        public List<CompletionStatusItem> CompletionStatuses { get; set; } = new();

        [JsonProperty("platforms")]
        public List<PlatformEntity> Platforms { get; set; } = new();

        [JsonProperty("genres")]
        public List<NamedEntity> Genres { get; set; } = new();

        [JsonProperty("features")]
        public List<NamedEntity> Features { get; set; } = new();

        [JsonProperty("tags")]
        public List<NamedEntity> Tags { get; set; } = new();

        [JsonProperty("series")]
        public List<NamedEntity> Series { get; set; } = new();

        [JsonProperty("active_addons")]
        public List<AddonDescriptor> ActiveAddons { get; set; } = new();
    }

    public class LibrarySummary
    {
        [JsonProperty("total_games")]
        public int TotalGames { get; set; }

        [JsonProperty("installed_games")]
        public int InstalledGames { get; set; }

        [JsonProperty("favorite_games")]
        public int FavoriteGames { get; set; }

        [JsonProperty("hidden_games")]
        public int HiddenGames { get; set; }

        [JsonProperty("total_playtime_seconds")]
        public long TotalPlaytimeSeconds { get; set; }

        [JsonProperty("total_play_count")]
        public long TotalPlayCount { get; set; }

        [JsonProperty("total_achievements_unlocked")]
        public int TotalAchievementsUnlocked { get; set; }

        [JsonProperty("total_achievements_possible")]
        public int TotalAchievementsPossible { get; set; }
    }

    public class SourceItem
    {
        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("icon_url")]
        public string? IconUrl { get; set; }
    }

    public class CompletionStatusItem
    {
        [JsonProperty("id")]
        public Guid Id { get; set; }

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("order")]
        public int Order { get; set; }
    }

    public class AddonDescriptor
    {
        [JsonProperty("id")]
        public string Id { get; set; } = string.Empty;

        [JsonProperty("name")]
        public string Name { get; set; } = string.Empty;

        [JsonProperty("version")]
        public string Version { get; set; } = "1.0.0";

        [JsonProperty("plugin_id")]
        public Guid PluginId { get; set; }

        [JsonProperty("is_enabled")]
        public bool IsEnabled { get; set; }

        [JsonProperty("has_data")]
        public bool HasData { get; set; }
    }
}
