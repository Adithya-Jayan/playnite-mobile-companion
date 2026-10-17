using System;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class ExtraMetadataExtractor : IAddonDataExtractor
    {
        public string AddonKey => "extra_metadata";
        public string DisplayName => "ExtraMetadataLoader";
        public Guid PluginId => Guid.Parse("705fdbca-e1fc-4004-b839-1d040b8b4429");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtraMetadata", "games");
            return Directory.Exists(dir);
        }

        public Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var gameDir = Path.Combine(playniteUserDataDir, "ExtraMetadata", "games", game.Id.ToString());
            if (!Directory.Exists(gameDir))
            {
                return Task.FromResult<object?>(null);
            }

            var logoPath = Path.Combine(gameDir, "Logo.png");
            var microtrailerPath = Path.Combine(gameDir, "VideoMicrotrailer.mp4");
            var trailerPath = Path.Combine(gameDir, "VideoTrailer.mp4");

            bool hasLogo = File.Exists(logoPath);
            bool hasMicrotrailer = File.Exists(microtrailerPath);
            bool hasTrailer = File.Exists(trailerPath);

            if (!hasLogo && !hasMicrotrailer && !hasTrailer)
            {
                return Task.FromResult<object?>(null);
            }

            object result = new
            {
                has_extra_metadata = true,
                has_logo = hasLogo,
                has_microtrailer = hasMicrotrailer,
                has_trailer = hasTrailer
            };

            return Task.FromResult<object?>(result);
        }
    }
}
