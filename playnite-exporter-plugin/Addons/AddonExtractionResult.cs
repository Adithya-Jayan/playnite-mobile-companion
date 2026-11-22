using System.Collections.Generic;
using PlayniteExporterPlugin.Models;

namespace PlayniteExporterPlugin.Addons
{
    /// <summary>
    /// Self-contained result of an addon extraction containing structured metadata,
    /// deterministic state hash, and CAS media uploads.
    /// </summary>
    public class AddonExtractionResult
    {
        public string AddonKey { get; set; } = string.Empty;
        public object? Data { get; set; }
        public string? StateHash { get; set; }
        public List<PlannedUpload> MediaUploads { get; set; } = new List<PlannedUpload>();

        public AddonExtractionResult() { }

        public AddonExtractionResult(string addonKey, object? data, string? stateHash = null, List<PlannedUpload>? mediaUploads = null)
        {
            AddonKey = addonKey;
            Data = data;
            StateHash = stateHash;
            MediaUploads = mediaUploads ?? new List<PlannedUpload>();
        }
    }
}
