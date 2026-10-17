using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class CheckDlcExtractor : IAddonDataExtractor
    {
        public string AddonKey => "check_dlc";
        public string DisplayName => "CheckDlc";
        public Guid PluginId => Guid.Parse("bf78d9af-6e79-4c73-aca6-c23a11a485ae");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "CheckDlc");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "CheckDlc",
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

            var dlcList = new List<object>();
            int ownedCount = 0;

            if (itemsArray != null)
            {
                foreach (var token in itemsArray)
                {
                    if (token is not JObject item) continue;

                    var isOwned = item.Value<bool?>("IsOwned") ?? false;
                    if (isOwned) ownedCount++;

                    var dlcId = item.Value<string>("DlcId") ?? Guid.NewGuid().ToString();
                    var name = item.Value<string>("Name") ?? "Unknown DLC";
                    var description = item.Value<string>("Description");
                    var imageUrl = item.Value<string>("Image");
                    var storeUrl = item.Value<string>("Url");
                    var price = item.Value<string>("Price");
                    var priceBase = item.Value<string>("PriceBase");

                    dlcList.Add(new
                    {
                        dlc_id = dlcId,
                        name = name,
                        description = description,
                        image_url = string.IsNullOrWhiteSpace(imageUrl) ? null : imageUrl,
                        store_url = string.IsNullOrWhiteSpace(storeUrl) ? null : storeUrl,
                        is_owned = isOwned,
                        price = price,
                        price_base = priceBase
                    });
                }
            }

            return new
            {
                has_dlc = dlcList.Count > 0,
                total_dlc_count = dlcList.Count,
                owned_dlc_count = ownedCount,
                items = dlcList
            };
        }
    }
}
