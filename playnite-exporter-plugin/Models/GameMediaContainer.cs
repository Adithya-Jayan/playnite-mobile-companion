using Newtonsoft.Json;

namespace PlayniteExporterPlugin.Models
{
    public class GameMediaContainer
    {
        [JsonProperty("cover")]
        public MediaImagePointer? Cover { get; set; }

        [JsonProperty("background")]
        public MediaImagePointer? Background { get; set; }

        [JsonProperty("icon")]
        public MediaImagePointer? Icon { get; set; }

        [JsonProperty("logo")]
        public MediaImagePointer? Logo { get; set; }

        [JsonProperty("microtrailer")]
        public MediaVideoPointer? Microtrailer { get; set; }

        [JsonProperty("trailer")]
        public MediaTrailerPointer? Trailer { get; set; }
    }

    public class MediaImagePointer
    {
        [JsonProperty("relative_path")]
        public string RelativePath { get; set; } = string.Empty;

        [JsonProperty("sha256")]
        public string Sha256 { get; set; } = string.Empty;

        [JsonProperty("format")]
        public string Format { get; set; } = "webp";

        [JsonProperty("width")]
        public int? Width { get; set; }

        [JsonProperty("height")]
        public int? Height { get; set; }
    }

    public class MediaVideoPointer
    {
        [JsonProperty("relative_path")]
        public string RelativePath { get; set; } = string.Empty;

        [JsonProperty("sha256")]
        public string Sha256 { get; set; } = string.Empty;

        [JsonProperty("size_bytes")]
        public long SizeBytes { get; set; }

        [JsonProperty("duration_seconds")]
        public double DurationSeconds { get; set; }
    }

    public class MediaTrailerPointer
    {
        [JsonProperty("relative_path")]
        public string? RelativePath { get; set; }

        [JsonProperty("sha256")]
        public string? Sha256 { get; set; }

        [JsonProperty("size_bytes")]
        public long? SizeBytes { get; set; }

        [JsonProperty("duration_seconds")]
        public double? DurationSeconds { get; set; }

        [JsonProperty("web_url")]
        public string? WebUrl { get; set; }
    }
}
