using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class GameActivityExtractor : IAddonDataExtractor
    {
        public string AddonKey => "game_activity";
        public string DisplayName => "GameActivity";
        public Guid PluginId => Guid.Parse("afbb1a0d-04a1-4d0c-9afa-c6e42ca855b4");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "GameActivity");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "GameActivity",
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

            var sessionsList = new List<object>();
            long totalTracked = root.Value<long?>("SessionPlaytime") ?? 0L;

            if (itemsArray != null)
            {
                foreach (var token in itemsArray)
                {
                    if (token is not JObject item) continue;

                    var dateSessionStr = item.Value<string>("DateSession");
                    DateTime dateSessionUtc = DateTime.MinValue;
                    if (!string.IsNullOrEmpty(dateSessionStr) && DateTime.TryParse(dateSessionStr, out var parsedDate))
                    {
                        dateSessionUtc = parsedDate.ToUniversalTime();
                    }

                    var elapsed = item.Value<long?>("ElapsedSeconds") ?? 0L;
                    var sourceId = item.Value<string>("SourceID");
                    var actionName = item.Value<string>("GameActionName") ?? "Default action";

                    var platformIds = new List<string>();
                    if (item["PlatformIDs"] is JArray pArray)
                    {
                        foreach (var p in pArray)
                        {
                            var pid = p.Value<string>();
                            if (!string.IsNullOrEmpty(pid)) platformIds.Add(pid!);
                        }
                    }

                    sessionsList.Add(new
                    {
                        date_session_utc = dateSessionUtc > DateTime.MinValue
                            ? dateSessionUtc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                            : "1970-01-01T00:00:00.000Z",
                        elapsed_seconds = elapsed,
                        source_id = string.IsNullOrEmpty(sourceId) ? null : sourceId,
                        platform_ids = platformIds,
                        action_name = actionName
                    });
                }
            }

            return new
            {
                has_sessions = sessionsList.Count > 0,
                total_tracked_seconds = totalTracked,
                session_count = sessionsList.Count,
                sessions = sessionsList
            };
        }
    }
}
