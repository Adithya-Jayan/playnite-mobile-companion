using System;
using System.Collections.Generic;
using System.Linq;
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
        private IReadOnlyList<IAddonDataExtractor> orderedExtractors = Array.Empty<IAddonDataExtractor>();
        private IAddonDataExtractor? playniteAchievementsExtractor;
        private IAddonDataExtractor? successStoryExtractor;

        public IReadOnlyList<IAddonDataExtractor> RegisteredExtractors => extractors.AsReadOnly();
        public IReadOnlyList<IAddonDataExtractor> OrderedExtractors => orderedExtractors;
        public IAddonDataExtractor? PlayniteAchievementsExtractor => playniteAchievementsExtractor;
        public IAddonDataExtractor? SuccessStoryExtractor => successStoryExtractor;

        public AddonExtractorRegistry()
        {
            Register(new PlayniteAchievementsExtractor());
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
            UpdateCaches();
        }

        private void UpdateCaches()
        {
            orderedExtractors = extractors.OrderBy(e => e.AddonKey, StringComparer.Ordinal).ToArray();
            playniteAchievementsExtractor = extractors.FirstOrDefault(e => e.AddonKey == "playnite_achievements" || e is PlayniteAchievementsExtractor);
            successStoryExtractor = extractors.FirstOrDefault(e => e.AddonKey == "success_story" || e is SuccessStoryExtractor);
        }

        public async Task<Dictionary<string, object?>> ExtractAllAsync(Game game, string userDataDir)
        {
            var results = new Dictionary<string, object?>();

            // Prioritize PlayniteAchievements over SuccessStory:
            // Check if PlayniteAchievements extractor exists and has valid data for this game first.
            var paExtractor = playniteAchievementsExtractor ?? extractors.FirstOrDefault(e => e.AddonKey == "playnite_achievements" || e is PlayniteAchievementsExtractor);
            bool paHasValidData = false;

            if (paExtractor != null)
            {
                try
                {
                    if (paExtractor.IsDataAvailable(userDataDir))
                    {
                        var paData = await paExtractor.ExtractDataAsync(game, userDataDir);
                        if (paData != null)
                        {
                            results[paExtractor.AddonKey] = paData;
                            paHasValidData = true;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Failed extracting addon data '{paExtractor.DisplayName}' for game '{game.Name}' ({game.Id}). Skipping addon.");
                }
            }

            foreach (var extractor in extractors)
            {
                if (extractor == paExtractor)
                {
                    continue; // Already processed
                }

                // If playnite_achievements has valid data, do NOT extract or export success_story for this game
                if (paHasValidData && (extractor == successStoryExtractor || extractor.AddonKey == "success_story" || extractor is SuccessStoryExtractor))
                {
                    continue;
                }

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

            // Post-condition safeguard: If playnite_achievements is present and non-null, remove success_story
            if (results.TryGetValue("playnite_achievements", out var achievementsData) && achievementsData != null)
            {
                results.Remove("success_story");
            }

            return results;
        }

        public Task<Dictionary<string, object?>> ExtractAllAddonDataAsync(Game game, string userDataDir)
        {
            return ExtractAllAsync(game, userDataDir);
        }
    }
}
