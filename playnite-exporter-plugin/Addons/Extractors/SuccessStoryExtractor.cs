using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class SuccessStoryExtractor : IAddonDataExtractor
    {
        public string AddonKey => "success_story";
        public string DisplayName => "SuccessStory";
        public Guid PluginId => Guid.Parse("cebe6d32-8c46-4459-b993-5a5189d60788");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "SuccessStory");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "SuccessStory",
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

            string? storeUrl = null;
            if (root["SourcesLink"] is JObject sourcesLink)
            {
                storeUrl = sourcesLink.Value<string>("Url");
            }

            var itemsList = new List<object>();
            int unlockedCount = 0;
            int totalCount = 0;
            double gamerscoreCurrent = 0;
            double gamerscoreTotal = 0;

            if (itemsArray != null)
            {
                totalCount = itemsArray.Count;
                foreach (var token in itemsArray)
                {
                    if (token is not JObject item) continue;

                    var dateUnlockedStr = item.Value<string>("DateUnlocked");
                    DateTime? dateUnlockedUtc = null;
                    if (!string.IsNullOrEmpty(dateUnlockedStr) && DateTime.TryParse(dateUnlockedStr, out var parsedDate))
                    {
                        if (parsedDate > DateTime.MinValue && parsedDate.Year > 1970)
                        {
                            dateUnlockedUtc = parsedDate.ToUniversalTime();
                        }
                    }

                    var isUnlocked = dateUnlockedUtc != null;
                    if (isUnlocked) unlockedCount++;

                    var score = item.Value<double?>("GamerScore") ?? 0;
                    gamerscoreTotal += score;
                    if (isUnlocked) gamerscoreCurrent += score;

                    bool noRarity = item.Value<bool?>("NoRarety") ?? false;
                    double? rarityPercent = null;
                    if (!noRarity && item["Percent"] != null)
                    {
                        var rawPercent = item.Value<double?>("Percent");
                        if (rawPercent.HasValue)
                        {
                            rarityPercent = Math.Round(rawPercent.Value, 2);
                        }
                    }

                    var urlUnlocked = item.Value<string>("UrlUnlocked") ?? item.Value<string>("ImageUnlocked") ?? string.Empty;
                    var urlLocked = item.Value<string>("UrlLocked") ?? item.Value<string>("ImageLocked") ?? string.Empty;

                    string? localIconUnlocked = null;
                    if (!string.IsNullOrEmpty(urlUnlocked))
                    {
                        var hash = ComputeMd5(urlUnlocked);
                        var localPath = Path.Combine(playniteUserDataDir, "cache", "SuccessStory", $"{hash}.jpg");
                        if (File.Exists(localPath)) localIconUnlocked = localPath;
                    }

                    object? progression = null;
                    if (item["Progression"] is JObject progObj)
                    {
                        var min = progObj.Value<double?>("Min") ?? 0;
                        var max = progObj.Value<double?>("Max") ?? 0;
                        var val = progObj.Value<double?>("Value") ?? 0;
                        progression = new { min, max, value = val };
                    }

                    itemsList.Add(new
                    {
                        name = item.Value<string>("Name") ?? string.Empty,
                        api_name = item.Value<string>("ApiName") ?? string.Empty,
                        description = item.Value<string>("Description") ?? string.Empty,
                        url_unlocked = urlUnlocked,
                        url_locked = urlLocked,
                        icon_unlocked = urlUnlocked,
                        icon_locked = urlLocked,
                        icon = urlUnlocked,
                        local_icon_path = localIconUnlocked,
                        date_unlocked_utc = dateUnlockedUtc?.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
                        percent = rarityPercent,
                        rarity_percentage = rarityPercent,
                        no_rarity = noRarity,
                        gamerscore = score,
                        is_hidden = item.Value<bool?>("IsHidden") ?? false,
                        category = item.Value<string>("Category") ?? "Base game",
                        progression = progression
                    });
                }
            }

            int lockedCount = Math.Max(0, totalCount - unlockedCount);
            double unlockedPercentage = totalCount > 0
                ? Math.Round(((double)unlockedCount / totalCount) * 100.0, 2)
                : 0.0;

            string? lastRefreshUtc = null;
            var refreshStr = root.Value<string>("DateLastRefresh");
            if (!string.IsNullOrEmpty(refreshStr) && DateTime.TryParse(refreshStr, out var parsedRefresh))
            {
                lastRefreshUtc = parsedRefresh.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
            }

            int? estimateTimeMin = null;
            int? estimateTimeMax = null;
            if (root["EstimateTime"] is JObject estObj)
            {
                estimateTimeMin = estObj.Value<int?>("EstimateTimeMin");
                estimateTimeMax = estObj.Value<int?>("EstimateTimeMax");
            }

            return new
            {
                has_achievements = totalCount > 0,
                store_url = storeUrl,
                sources_link = storeUrl,
                total_count = totalCount,
                unlocked_count = unlockedCount,
                locked_count = lockedCount,
                unlocked_percentage = unlockedPercentage,
                gamerscore_current = gamerscoreCurrent,
                gamerscore_total = gamerscoreTotal,
                last_refresh_utc = lastRefreshUtc,
                estimate_time_min = estimateTimeMin,
                estimate_time_max = estimateTimeMax,
                items = itemsList,
                achievements = itemsList
            };
        }

        private static string ComputeMd5(string input)
        {
            using (var md5 = MD5.Create())
            {
                var bytes = md5.ComputeHash(Encoding.UTF8.GetBytes(input));
                var sb = new StringBuilder(bytes.Length * 2);
                for (int i = 0; i < bytes.Length; i++)
                {
                    sb.Append(bytes[i].ToString("x2"));
                }
                return sb.ToString();
            }
        }
    }
}
