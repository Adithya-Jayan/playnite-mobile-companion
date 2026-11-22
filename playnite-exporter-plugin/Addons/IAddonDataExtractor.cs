using System;
using System.Threading.Tasks;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons
{
    public interface IAddonDataExtractor
    {
        string AddonKey { get; }
        string DisplayName { get; }
        Guid PluginId { get; }
        bool IsDataAvailable(string playniteUserDataDir);
        Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir);
        string? GetStateHash(Game game, string playniteUserDataDir);

        /// <summary>
        /// Deepened self-contained extraction yielding structured metadata, state hash, and CAS media uploads.
        /// </summary>
        Task<AddonExtractionResult> ExtractAsync(Game game, string playniteUserDataDir);
    }
}
