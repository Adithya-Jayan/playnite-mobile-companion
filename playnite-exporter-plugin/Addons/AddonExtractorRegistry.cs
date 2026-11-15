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

        /// <summary>
        /// Returns the active extractors for the specified game in deterministic order.
        /// When PlayniteAchievements has valid data or state for the game, SuccessStory is suppressed.
        /// </summary>
        public IReadOnlyList<IAddonDataExtractor> GetActiveExtractorsForGame(Game game, string userDataDir)
        {
            var playniteAchievementsExtractor = this.playniteAchievementsExtractor ??
                extractors.FirstOrDefault(e => e.AddonKey == "playnite_achievements" || e is PlayniteAchievementsExtractor);
            var successStoryExtractor = this.successStoryExtractor ??
                extractors.FirstOrDefault(e => e.AddonKey == "success_story" || e is SuccessStoryExtractor);

            bool playniteAchievementsActive = false;
            if (playniteAchievementsExtractor != null)
            {
                try
                {
                    var achievementsStateHash = playniteAchievementsExtractor.GetStateHash(game, userDataDir);
                    playniteAchievementsActive = !string.IsNullOrEmpty(achievementsStateHash);
                }
                catch
                {
                    playniteAchievementsActive = false;
                }
            }

            var allExtractors = orderedExtractors.Count > 0
                ? orderedExtractors
                : extractors.OrderBy(e => e.AddonKey, StringComparer.Ordinal).ToArray();

            var active = new List<IAddonDataExtractor>();
            foreach (var extractor in allExtractors)
            {
                if (playniteAchievementsActive && (extractor == successStoryExtractor || extractor.AddonKey == "success_story" || extractor is SuccessStoryExtractor))
                {
                    continue; // Suppressed by PlayniteAchievements
                }

                active.Add(extractor);
            }

            return active.AsReadOnly();
        }

        public async Task<Dictionary<string, object?>> ExtractAllAsync(Game game, string userDataDir)
        {
            var results = new Dictionary<string, object?>();

            // Prioritize PlayniteAchievements over SuccessStory:
            // Check if PlayniteAchievements extractor exists and has valid data for this game first.
            var playniteAchievementsExtractor = this.playniteAchievementsExtractor ??
                extractors.FirstOrDefault(e => e.AddonKey == "playnite_achievements" || e is PlayniteAchievementsExtractor);
            var successStoryExtractor = this.successStoryExtractor ??
                extractors.FirstOrDefault(e => e.AddonKey == "success_story" || e is SuccessStoryExtractor);
            bool playniteAchievementsHasValidData = false;

            if (playniteAchievementsExtractor != null)
            {
                try
                {
                    if (playniteAchievementsExtractor.IsDataAvailable(userDataDir))
                    {
                        var data = await playniteAchievementsExtractor.ExtractDataAsync(game, userDataDir);
                        if (data != null)
                        {
                            results[playniteAchievementsExtractor.AddonKey] = data;
                            playniteAchievementsHasValidData = true;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Failed extracting addon data '{playniteAchievementsExtractor.DisplayName}' for game '{game.Name}' ({game.Id}). Skipping addon.");
                }
            }

            foreach (var extractor in extractors)
            {
                if (extractor == playniteAchievementsExtractor)
                {
                    continue; // Already processed
                }

                // If playnite_achievements has valid data, do NOT extract or export success_story for this game
                if (playniteAchievementsHasValidData && (extractor == successStoryExtractor || extractor.AddonKey == "success_story" || extractor is SuccessStoryExtractor))
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
            if (results.TryGetValue("playnite_achievements", out var finalAchievementsData) && finalAchievementsData != null)
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
