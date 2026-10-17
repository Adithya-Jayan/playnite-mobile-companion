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
    }
}
