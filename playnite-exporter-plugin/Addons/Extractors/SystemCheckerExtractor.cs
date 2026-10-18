using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class SystemCheckerExtractor : IAddonDataExtractor
    {
        public string AddonKey => "system_checker";
        public string DisplayName => "SystemChecker";
        public Guid PluginId => Guid.Parse("e248b230-6edf-41ea-a3c3-7861fa267263");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "SystemChecker");
            return Directory.Exists(dir);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var filePath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "SystemChecker",
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
                return new { has_requirements = false, minimum = (object?)null, recommended = (object?)null };
            }

            object? minSpecs = null;
            object? recSpecs = null;

            foreach (var token in itemsArray)
            {
                if (token is not JObject item) continue;

                var isMin = item.Value<bool?>("IsMinimum") ?? true;
                var osList = ToStringList(item["Os"]);
                var cpuList = ToStringList(item["Cpu"]);
                var gpuList = ToStringList(item["Gpu"]);
                var ramBytes = item.Value<double?>("Ram");
                var ramUsage = item.Value<string>("RamUsage");
                var storageBytes = item.Value<double?>("Storage");
                var storageUsage = item.Value<string>("StorageUsage");

                if (!HasRealSpecs(osList, cpuList, gpuList, ramBytes, storageBytes))
                {
                    continue;
                }

                var specObj = new
                {
                    os = osList,
                    cpu = cpuList,
                    gpu = gpuList,
                    ram_bytes = ramBytes,
                    ram_usage = ramUsage,
                    storage_bytes = storageBytes,
                    storage_usage = storageUsage
                };

                if (isMin && minSpecs == null) minSpecs = specObj;
                else if (!isMin && recSpecs == null) recSpecs = specObj;
            }

            var hasRequirements = minSpecs != null || recSpecs != null;

            return new
            {
                has_requirements = hasRequirements,
                minimum = minSpecs,
                recommended = recSpecs
            };
        }

        private static bool HasRealSpecs(List<string> os, List<string> cpu, List<string> gpu, double? ram, double? storage)
        {
            var hasOs = os != null && os.Any(s => !string.IsNullOrWhiteSpace(s));
            var hasCpu = cpu != null && cpu.Any(s => !string.IsNullOrWhiteSpace(s));
            var hasGpu = gpu != null && gpu.Any(s => !string.IsNullOrWhiteSpace(s));
            var hasRam = ram.HasValue && ram.Value > 0.0;
            var hasStorage = storage.HasValue && storage.Value > 0.0;

            return hasOs || hasCpu || hasGpu || hasRam || hasStorage;
        }

        private static List<string> ToStringList(JToken? token)
        {
            var list = new List<string>();
            if (token is JArray arr)
            {
                foreach (var item in arr)
                {
                    var str = item.Value<string>();
                    if (!string.IsNullOrEmpty(str)) list.Add(str!);
                }
            }
            return list;
        }
    }
}
