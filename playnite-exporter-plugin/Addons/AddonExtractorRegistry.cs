using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons.Extractors;

namespace PlayniteExporterPlugin.Addons
{
    public class AddonExtractorRegistry
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly List<IAddonDataExtractor> extractors = new();

        public IReadOnlyList<IAddonDataExtractor> RegisteredExtractors => extractors.AsReadOnly();

        public AddonExtractorRegistry()
        {
            Register(new SuccessStoryExtractor());
            Register(new HowLongToBeatExtractor());
            Register(new GameActivityExtractor());
            Register(new ExtraMetadataExtractor());
            Register(new CheckDlcExtractor());
            Register(new SystemCheckerExtractor());
            Register(new SteamReviewsExtractor());
            Register(new SteamScreenshotsExtractor());
            Register(new PlayerActivitiesExtractor());
        }

        public void Register(IAddonDataExtractor extractor)
        {
            if (extractor == null) throw new ArgumentNullException(nameof(extractor));
            extractors.Add(extractor);
        }

        public async Task<Dictionary<string, object?>> ExtractAllAsync(Game game, string userDataDir)
        {
            var results = new Dictionary<string, object?>();

            foreach (var extractor in extractors)
            {
                try
                {
                    if (!extractor.IsDataAvailable(userDataDir))
                    {
                        continue;
                    }

                    var data = await extractor.ExtractDataAsync(game, userDataDir);
                    if (data != null)
                    {
                        results[extractor.AddonKey] = data;
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Failed extracting addon data '{extractor.DisplayName}' for game '{game.Name}' ({game.Id}). Skipping addon.");
                }
            }

            return results;
        }
    }
}
