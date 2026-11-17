using System;
using System.Collections.Generic;
using System.Data.SQLite;
using System.Globalization;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Addons.Extractors
{
    public class PlayniteAchievementsExtractor : IAddonDataExtractor
    {
        public string AddonKey => "playnite_achievements";
        public string DisplayName => "Playnite Achievements";
        public Guid PluginId => Guid.Parse("e6aad2c9-6e06-4d8d-ac55-ac3b252b5f7b");

        public bool IsDataAvailable(string playniteUserDataDir)
        {
            var dbPath = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "achievement_cache.db");
            return File.Exists(dbPath);
        }

        public async Task<object?> ExtractDataAsync(Game game, string playniteUserDataDir)
        {
            if (game == null) return null;

            var dbPath = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "achievement_cache.db");
            if (!File.Exists(dbPath)) return null;

            var csb = new SQLiteConnectionStringBuilder
            {
                DataSource = dbPath,
                ReadOnly = true
            };

            using var connection = new SQLiteConnection(csb.ToString());
            await connection.OpenAsync();

            long? internalGameId = null;
            using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = "SELECT Id FROM Games WHERE PlayniteGameId = @playniteId COLLATE NOCASE LIMIT 1;";
                cmd.Parameters.AddWithValue("@playniteId", game.Id.ToString());
                var val = await cmd.ExecuteScalarAsync();
                if (val != null && val != DBNull.Value)
                {
                    internalGameId = Convert.ToInt64(val);
                }
            }

            if (!internalGameId.HasValue) return null;

            long? userGameProgressId = null;
            int totalAchievementsFromProgress = 0;
            string? lastUpdatedUtc = null;

            using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = @"
                    SELECT p.Id, p.TotalAchievements, p.LastUpdatedUtc
                    FROM UserGameProgress p
                    INNER JOIN Users u ON p.UserId = u.Id
                    WHERE p.GameId = @gameId AND u.IsCurrentUser = 1
                    ORDER BY p.LastUpdatedUtc DESC
                    LIMIT 1;";
                cmd.Parameters.AddWithValue("@gameId", internalGameId.Value);

                using var reader = await cmd.ExecuteReaderAsync();
                {
                    if (await reader.ReadAsync())
                    {
                        userGameProgressId = reader.GetInt64(0);
                        totalAchievementsFromProgress = reader.IsDBNull(1) ? 0 : reader.GetInt32(1);
                        if (!reader.IsDBNull(2))
                        {
                            lastUpdatedUtc = reader.GetString(2);
                        }
                    }
                }
            }

            if (!userGameProgressId.HasValue || totalAchievementsFromProgress == 0)
            {
                return null;
            }

            var itemsList = new List<object>();
            int unlockedCount = 0;
            double gamerscoreCurrent = 0;
            double gamerscoreTotal = 0;
            var pluginDir = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString());

            using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = @"
                    SELECT 
                        d.ApiName,
                        d.DisplayName,
                        d.Description,
                        d.UnlockedIconPath,
                        d.LockedIconPath,
                        d.Points,
                        d.Category,
                        d.Hidden,
                        d.GlobalPercentUnlocked,
                        d.ProgressMax,
                        ua.Unlocked,
                        ua.UnlockTimeUtc,
                        ua.ProgressNum,
                        ua.ProgressDenom
                    FROM AchievementDefinitions d
                    LEFT JOIN UserAchievements ua 
                        ON d.Id = ua.AchievementDefinitionId 
                        AND ua.UserGameProgressId = @progressId
                    WHERE d.GameId = @gameId;";
                cmd.Parameters.AddWithValue("@gameId", internalGameId.Value);
                cmd.Parameters.AddWithValue("@progressId", userGameProgressId.Value);

                using var reader = await cmd.ExecuteReaderAsync();
                {
                    while (await reader.ReadAsync())
                    {
                        var apiName = reader.IsDBNull(0) ? string.Empty : reader.GetString(0);
                        var displayName = reader.IsDBNull(1) ? string.Empty : reader.GetString(1);
                        var description = reader.IsDBNull(2) ? string.Empty : reader.GetString(2);
                        var unlockedIcon = reader.IsDBNull(3) ? null : reader.GetString(3);
                        var lockedIcon = reader.IsDBNull(4) ? null : reader.GetString(4);
                        double points = reader.IsDBNull(5) ? 0 : Convert.ToDouble(reader.GetValue(5));
                        var category = reader.IsDBNull(6) ? "Default" : reader.GetString(6);
                        bool isHidden = !reader.IsDBNull(7) && Convert.ToInt32(reader.GetValue(7)) == 1;

                        double? rarityPercent = null;
                        if (!reader.IsDBNull(8))
                        {
                            rarityPercent = Math.Round(Convert.ToDouble(reader.GetValue(8)), 2);
                        }

                        int? progressMax = reader.IsDBNull(9) ? null : (int?)Convert.ToInt32(reader.GetValue(9));

                        bool isUnlocked = !reader.IsDBNull(10) && Convert.ToInt32(reader.GetValue(10)) == 1;
                        DateTime? dateUnlockedUtc = null;
                        if (isUnlocked && !reader.IsDBNull(11))
                        {
                            var dateStr = reader.GetString(11);
                            if (DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var parsedDate))
                            {
                                if (parsedDate > DateTime.MinValue && parsedDate.Year > 1970)
                                {
                                    dateUnlockedUtc = parsedDate.ToUniversalTime();
                                }
                            }
                        }

                        int? progressNum = reader.IsDBNull(12) ? null : (int?)Convert.ToInt32(reader.GetValue(12));
                        int? progressDenom = reader.IsDBNull(13) ? null : (int?)Convert.ToInt32(reader.GetValue(13));

                        if (isUnlocked)
                        {
                            unlockedCount++;
                            gamerscoreCurrent += points;
                        }
                        gamerscoreTotal += points;

                        var safeApiName = string.Concat(apiName.Split(Path.GetInvalidFileNameChars()));
                        var unlockedRel = !string.IsNullOrEmpty(unlockedIcon)
                            ? unlockedIcon!
                            : Path.Combine("icon_cache", game.Id.ToString(), "original", $"{safeApiName}.jpg");

                        string? localUnlockedPath = null;
                        try
                        {
                            var candidateUnlocked = Path.IsPathRooted(unlockedRel)
                                ? unlockedRel
                                : Path.Combine(pluginDir, unlockedRel);

                            if (File.Exists(candidateUnlocked))
                            {
                                localUnlockedPath = candidateUnlocked;
                            }
                        }
                        catch
                        {
                            localUnlockedPath = null;
                        }

                        var lockedRel = !string.IsNullOrEmpty(lockedIcon)
                            ? lockedIcon!
                            : unlockedRel;

                        object? progression = null;
                        if (progressNum.HasValue || progressDenom.HasValue || progressMax.HasValue)
                        {
                            var maxVal = progressDenom ?? progressMax ?? 0;
                            var currentVal = progressNum ?? 0;
                            progression = new { min = 0, max = maxVal, value = currentVal };
                        }

                        itemsList.Add(new
                        {
                            name = string.IsNullOrEmpty(displayName) ? apiName : displayName,
                            api_name = apiName,
                            description = description,
                            unlocked = isUnlocked,
                            is_unlocked = isUnlocked,
                            url_unlocked = unlockedRel,
                            url_locked = lockedRel,
                            icon_unlocked = unlockedRel,
                            icon_locked = lockedRel,
                            icon = unlockedRel,
                            local_icon_path = localUnlockedPath,
                            date_unlocked_utc = dateUnlockedUtc?.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"),
                            percent = rarityPercent,
                            rarity_percent = rarityPercent,
                            rarity_percentage = rarityPercent,
                            no_rarity = rarityPercent == null,
                            gamerscore = points,
                            points = points,
                            is_hidden = isHidden,
                            category = string.IsNullOrWhiteSpace(category) ? "Default" : category,
                            progression = progression
                        });
                    }
                }
            }

            int totalCount = itemsList.Count;
            if (totalCount == 0) return null;

            int lockedCount = Math.Max(0, totalCount - unlockedCount);
            double unlockedPercentage = totalCount > 0
                ? Math.Round(((double)unlockedCount / totalCount) * 100.0, 2)
                : 0.0;

            string? formattedLastRefreshUtc = null;
            if (!string.IsNullOrEmpty(lastUpdatedUtc) && DateTime.TryParse(lastUpdatedUtc, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var parsedRefresh))
            {
                formattedLastRefreshUtc = parsedRefresh.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
            }

            return new
            {
                has_achievements = totalCount > 0,
                total_count = totalCount,
                unlocked_count = unlockedCount,
                locked_count = lockedCount,
                unlocked_percentage = unlockedPercentage,
                gamerscore_current = gamerscoreCurrent,
                gamerscore_total = gamerscoreTotal,
                last_refresh_utc = formattedLastRefreshUtc,
                items = itemsList,
                achievements = itemsList
            };
        }

        private static readonly object CacheLock = new();
        private static string? cachedDbKey;
        private static readonly Dictionary<string, string> progressStateCache = new(StringComparer.OrdinalIgnoreCase);

        public string? GetStateHash(Game game, string playniteUserDataDir)
        {
            if (game == null) return null;

            try
            {
                var dbPath = Path.Combine(playniteUserDataDir, "ExtensionsData", PluginId.ToString(), "achievement_cache.db");
                if (!File.Exists(dbPath)) return null;

                var fi = new FileInfo(dbPath);
                var currentKey = $"{fi.FullName}|{fi.LastWriteTimeUtc.Ticks}|{fi.Length}";

                lock (CacheLock)
                {
                    if (cachedDbKey != currentKey)
                    {
                        progressStateCache.Clear();
                        try
                        {
                            var csb = new SQLiteConnectionStringBuilder
                            {
                                DataSource = dbPath,
                                ReadOnly = true
                            };

                            using var connection = new SQLiteConnection(csb.ToString());
                            connection.Open();

                            using var cmd = connection.CreateCommand();
                            cmd.CommandText = @"
                                SELECT g.PlayniteGameId, u.AchievementsUnlocked, u.TotalAchievements, u.LastUpdatedUtc
                                FROM UserGameProgress u
                                JOIN Games g ON u.GameId = g.Id
                                WHERE g.PlayniteGameId IS NOT NULL;";

                            using var reader = cmd.ExecuteReader();
                            while (reader.Read())
                            {
                                var playniteId = reader.IsDBNull(0) ? null : reader.GetString(0);
                                if (!string.IsNullOrEmpty(playniteId))
                                {
                                    var unlocked = reader.IsDBNull(1) ? 0 : Convert.ToInt32(reader.GetValue(1));
                                    var total = reader.IsDBNull(2) ? 0 : Convert.ToInt32(reader.GetValue(2));
                                    var lastUpdatedUtc = reader.IsDBNull(3) ? string.Empty : reader.GetString(3);
                                    progressStateCache[playniteId] = $"{unlocked}_{total}_{lastUpdatedUtc}";
                                }
                            }
                            cachedDbKey = currentKey;
                        }
                        catch
                        {
                            cachedDbKey = null;
                        }
                    }

                    if (progressStateCache.TryGetValue(game.Id.ToString(), out var cachedHash))
                    {
                        return cachedHash;
                    }
                }

                // Fallback: direct query with COLLATE NOCASE
                var fallbackCsb = new SQLiteConnectionStringBuilder
                {
                    DataSource = dbPath,
                    ReadOnly = true
                };

                using (var connection = new SQLiteConnection(fallbackCsb.ToString()))
                {
                    connection.Open();
                    using var cmd = connection.CreateCommand();
                    cmd.CommandText = @"
                        SELECT u.AchievementsUnlocked, u.TotalAchievements, u.LastUpdatedUtc
                        FROM UserGameProgress u
                        JOIN Games g ON u.GameId = g.Id
                        WHERE g.PlayniteGameId = @playniteId COLLATE NOCASE
                        LIMIT 1;";
                    cmd.Parameters.AddWithValue("@playniteId", game.Id.ToString());

                    using var reader = cmd.ExecuteReader();
                    if (reader.Read())
                    {
                        var unlocked = reader.IsDBNull(0) ? 0 : Convert.ToInt32(reader.GetValue(0));
                        var total = reader.IsDBNull(1) ? 0 : Convert.ToInt32(reader.GetValue(1));
                        var lastUpdatedUtc = reader.IsDBNull(2) ? string.Empty : reader.GetString(2);
                        var hash = $"{unlocked}_{total}_{lastUpdatedUtc}";
                        lock (CacheLock)
                        {
                            progressStateCache[game.Id.ToString()] = hash;
                        }
                        return hash;
                    }
                }

                return null;
            }
            catch
            {
                return null;
            }
        }
    }
}
