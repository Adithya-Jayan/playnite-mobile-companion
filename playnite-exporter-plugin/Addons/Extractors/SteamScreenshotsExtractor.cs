using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class SteamScreenshotsExtractor : IAddonDataExtractor
    {
        public string AddonKey => "steam_screenshots";
        public string DisplayName => "SteamScreenshots";
        public Guid PluginId => Guid.Parse("8e77fe31-5e62-41e2-8fa2-64844cfd5b6b");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "appdetails");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            if (string.IsNullOrEmpty(game.GameId)) return null;

            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "appdetails",
                $"{game.GameId}_appdetails.json"
            );

            if (!File.Exists(filePath)) return null;

            string jsonContent;
            using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var reader = new StreamReader(stream))
            {
                jsonContent = await reader.ReadToEndAsync();
            }

            if (string.IsNullOrWhiteSpace(jsonContent)) return null;

            var root = JObject.Parse(jsonContent);
            var screenshotsArray = root["screenshots"] as JArray;

            if (screenshotsArray == null || screenshotsArray.Count == 0)
            {
                return null;
            }

            var items = new List<object>();
            foreach (var token in screenshotsArray)
            {
                if (token is not JObject sObj) continue;

                var id = sObj.Value<int?>("id") ?? items.Count;
                var thumb = sObj.Value<string>("path_thumbnail");
                var full = sObj.Value<string>("path_full");

                if (!string.IsNullOrEmpty(thumb) && !string.IsNullOrEmpty(full))
                {
                    items.Add(new
                    {
                        id = id,
                        thumbnail_url = thumb,
                        full_url = full
                    });
                }
            }

            if (items.Count == 0) return null;

            return new
            {
                has_screenshots = true,
                items = items
            };
        }
    }
}
