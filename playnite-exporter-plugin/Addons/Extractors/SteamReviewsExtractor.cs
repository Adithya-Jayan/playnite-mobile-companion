using System;
using System.IO;
using System.Threading.Tasks;
using LiteDB;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class SteamReviewsExtractor : IAddonDataExtractor
    {
        public string AddonKey => "steam_reviews";
        public string DisplayName => "SteamReviews";
        public Guid PluginId => Guid.Parse("ca24e37a-76d9-49bf-89ab-d3cba4a54bd1");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dbPath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "reviewsDatabase.db"
            );
            return File.Exists(dbPath);
        }

        public Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            var dbPath = Path.Combine(
                playniteUserDataDir,
                "ExtensionsData",
                PluginId.ToString(),
                "reviewsDatabase.db"
            );

            if (!File.Exists(dbPath))
            {
                return Task.FromResult<object?>(null);
            }

            try
            {
                // Open with shared read/write access to avoid any lock contention with running Playnite
                using var fileStream = new System.IO.FileStream(dbPath, System.IO.FileMode.Open, System.IO.FileAccess.Read, System.IO.FileShare.ReadWrite);
                using var db = new LiteDatabase(fileStream);

                var collection = db.GetCollection("ReviewsResponseRecord_collection");
                if (collection == null)
                {
                    return Task.FromResult<object?>(null);
                }

                var doc = collection.FindById(new BsonValue(game.Id));
                if (doc == null && !string.IsNullOrEmpty(game.GameId))
                {
                    // Fallback to checking by CacheKey if needed
                    doc = collection.FindOne(Query.EQ("CacheKey", game.GameId));
                }

                if (doc == null || !doc.ContainsKey("Response"))
                {
                    return Task.FromResult<object?>(null);
                }

                var responseDoc = doc["Response"].AsDocument;
                if (responseDoc == null || !responseDoc.ContainsKey("QuerySummary"))
                {
                    return Task.FromResult<object?>(null);
                }

                var summary = responseDoc["QuerySummary"].AsDocument;
                if (summary == null)
                {
                    return Task.FromResult<object?>(null);
                }

                var reviewScoreDesc = summary.ContainsKey("ReviewScoreDesc") ? summary["ReviewScoreDesc"].AsString : null;
                var reviewScore = summary.ContainsKey("ReviewScore") ? (int?)summary["ReviewScore"].AsInt32 : null;
                var totalPositive = summary.ContainsKey("TotalPositive") ? (int?)summary["TotalPositive"].AsInt32 : null;
                var totalNegative = summary.ContainsKey("TotalNegative") ? (int?)summary["TotalNegative"].AsInt32 : null;
                var totalReviews = summary.ContainsKey("TotalReviews") ? (int?)summary["TotalReviews"].AsInt32 : null;

                object result = new
                {
                    has_reviews = true,
                    review_score_desc = reviewScoreDesc,
                    review_score = reviewScore,
                    total_positive = totalPositive,
                    total_negative = totalNegative,
                    total_reviews = totalReviews
                };

                return Task.FromResult<object?>(result);
            }
            catch
            {
                return Task.FromResult<object?>(null);
            }
        }
    }
}
