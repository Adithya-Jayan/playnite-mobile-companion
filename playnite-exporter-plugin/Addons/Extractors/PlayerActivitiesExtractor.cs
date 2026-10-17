using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class PlayerActivitiesExtractor : IAddonDataExtractor
    {
        public string AddonKey => "player_activities";
        public string DisplayName => "PlayerActivities";
        public Guid PluginId => Guid.Parse("3dbe2ee4-d6c9-4c09-b377-7a086369603e");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "PlayerActivities");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "PlayerActivities",
                $"{game.Id}.json"
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
            var itemsArray = root["Items"] as JArray;

            if (itemsArray == null || itemsArray.Count == 0)
            {
                return null;
            }

            var items = new List<object>();
            foreach (var token in itemsArray)
            {
                if (token is not JObject item) continue;

                var dateStr = item.Value<string>("DateActivity");
                DateTime dateUtc = DateTime.MinValue;
                if (!string.IsNullOrEmpty(dateStr) && DateTime.TryParse(dateStr, out var parsedDate))
                {
                    dateUtc = parsedDate.ToUniversalTime();
                }

                var type = item.Value<int?>("Type") ?? 0;
                var val = item.Value<double?>("Value") ?? 0;

                string activityName = type switch
                {
                    1 => "Playnite Opened",
                    2 => "Game Installed",
                    3 => "Game Uninstalled",
                    4 => "Achievement Unlocked",
                    5 => "Game Session",
                    6 => "Game Added",
                    _ => $"Activity Type {type}"
                };

                items.Add(new
                {
                    date_utc = dateUtc > DateTime.MinValue
                        ? dateUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        : "1970-01-01T00:00:00.000Z",
                    activity_type = type,
                    activity_name = activityName,
                    value = val
                });
            }

            if (items.Count == 0) return null;

            return new
            {
                has_activities = true,
                items = items
            };
        }
    }
}
