using System;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class HowLongToBeatExtractor : IAddonDataExtractor
    {
        public string AddonKey => "how_long_to_beat";
        public string DisplayName => "HowLongToBeat";
        public Guid PluginId => Guid.Parse("e08cd51f-9c9a-4ee3-a094-fde03b55492f");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "HowLongToBeat");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "HowLongToBeat",
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

            var firstItem = itemsArray[0] as JObject;
            if (firstItem == null) return null;

            var hltbData = firstItem["GameHltbData"] as JObject;
            if (hltbData == null) return null;

            return new
            {
                has_data = true,
                hltb_id = firstItem.Value<string>("Id"),
                url = firstItem.Value<string>("Url"),
                main_story_seconds = hltbData.Value<long?>("MainStoryClassic") ?? 0L,
                main_extra_seconds = hltbData.Value<long?>("MainExtraClassic") ?? 0L,
                completionist_seconds = hltbData.Value<long?>("CompletionistClassic") ?? 0L,
                solo_seconds = hltbData.Value<long?>("SoloClassic") ?? 0L,
                coop_seconds = hltbData.Value<long?>("CoOpClassic") ?? 0L,
                vs_seconds = hltbData.Value<long?>("VsClassic") ?? 0L
            };
        }
    }
}
