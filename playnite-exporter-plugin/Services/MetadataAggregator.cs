using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Models;

namespace PlayniteExporterPlugin.Services
{
    public class MetadataAggregator
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly IPlayniteAPI api;
        private readonly AddonExtractorRegistry addonRegistry;
        private readonly MediaProcessor mediaProcessor;

        public MetadataAggregator(
            IPlayniteAPI api,
            AddonExtractorRegistry addonRegistry,
            MediaProcessor mediaProcessor)
        {
            this.api = api;
            this.addonRegistry = addonRegistry;
            this.mediaProcessor = mediaProcessor;
        }

        public async Task<(UnifiedGamePayload Payload, List<PlannedUpload> MediaUploads)> BuildGamePayloadAsync(
            Game game,
            string userDataDir)
        {
            // Resolve Relational entities
            NamedEntity? source = ResolveSource(game);

            NamedEntity? status = null;
            if (game.CompletionStatusId != Guid.Empty && api.Database?.CompletionStatuses != null)
            {
                var cs = api.Database.CompletionStatuses.Get(game.CompletionStatusId);
                if (cs != null) status = new NamedEntity { Id = cs.Id, Name = cs.Name };
            }

            var platforms = new List<PlatformEntity>();
            if (game.PlatformIds != null && api.Database?.Platforms != null)
            {
                foreach (var pid in game.PlatformIds)
                {
                    var p = api.Database.Platforms.Get(pid);
                    if (p != null)
                    {
                        platforms.Add(new PlatformEntity
                        {
                            Id = p.Id,
                            Name = p.Name,
                            SpecId = null // Playnite 10 / standard platform spec ID if present
                        });
                    }
                }
            }

            var genres = ResolveEntities(game.GenreIds, api.Database?.Genres);
            var developers = ResolveEntities(game.DeveloperIds, api.Database?.Companies);
            var publishers = ResolveEntities(game.PublisherIds, api.Database?.Companies);
            var categories = ResolveEntities(game.CategoryIds, api.Database?.Categories);
            var tags = ResolveEntities(game.TagIds, api.Database?.Tags);
            var features = ResolveEntities(game.FeatureIds, api.Database?.Features);
            var series = ResolveEntities(game.SeriesIds, api.Database?.Series);
            var ageRatings = ResolveEntities(game.AgeRatingIds, api.Database?.AgeRatings);
            var regions = ResolveEntities(game.RegionIds, api.Database?.Regions);

            var links = new List<LinkEntity>();
            if (game.Links != null)
            {
                foreach (var link in game.Links)
                {
                    if (link != null && !string.IsNullOrEmpty(link.Url))
                    {
                        var sanitizedName = SanitizeLinkName(link.Name, link.Url);
                        links.Add(new LinkEntity { Name = sanitizedName, Url = link.Url });
                    }
                }
            }

            // Media
            var (media, mediaUploads) = await mediaProcessor.ResolveGameMediaAsync(game, userDataDir);

            // Addons
            var addons = await addonRegistry.ExtractAllAsync(game, userDataDir);

            // Duplicate copies & DuplicateHider resolution
            var (isDuplicate, duplicateGroupId, otherCopies) = ResolveDuplicateCopies(game);

            var payload = new UnifiedGamePayload
            {
                SchemaVersion = "1.0.0",
                Id = game.Id,
                GameId = game.GameId ?? string.Empty,
                PluginId = game.PluginId,
                Name = game.Name ?? "Unknown Game",
                SortingName = string.IsNullOrWhiteSpace(game.SortingName) ? (game.Name ?? "") : game.SortingName,
                Description = game.Description,
                Notes = game.Notes,
                PlaytimeSeconds = (long)game.Playtime,
                PlayCount = (long)game.PlayCount,
                AddedUtc = game.Added?.ToUniversalTime(),
                ModifiedUtc = game.Modified?.ToUniversalTime(),
                LastActivityUtc = game.LastActivity?.ToUniversalTime(),
                RecentActivityUtc = game.RecentActivity?.ToUniversalTime(),
                ReleaseDate = game.ReleaseDate?.ToString(),
                IsInstalled = game.IsInstalled,
                InstallDirectory = game.InstallDirectory,
                InstallSizeBytes = (long?)game.InstallSize,
                Hidden = game.Hidden,
                IsDuplicate = isDuplicate,
                DuplicateGroupId = duplicateGroupId,
                OtherCopies = otherCopies,
                Favorite = game.Favorite,
                Version = game.Version,
                UserScore = game.UserScore,
                CriticScore = game.CriticScore,
                CommunityScore = game.CommunityScore,
                Source = source,
                CompletionStatus = status,
                Platforms = platforms,
                Genres = genres,
                Developers = developers,
                Publishers = publishers,
                Categories = categories,
                Tags = tags,
                Features = features,
                Series = series,
                AgeRatings = ageRatings,
                Regions = regions,
                Links = links,
                Media = media,
                Addons = addons
            };

            return (payload, mediaUploads);
        }

        public ManifestPayload BuildManifest(IEnumerable<Game> games, string userDataDir)
        {
            var gameList = games.ToList();

            var summary = new LibrarySummary
            {
                TotalGames = gameList.Count,
                InstalledGames = gameList.Count(g => g.IsInstalled),
                FavoriteGames = gameList.Count(g => g.Favorite),
                HiddenGames = gameList.Count(g => g.Hidden),
                TotalPlaytimeSeconds = (long)gameList.Sum(g => (double)g.Playtime),
                TotalPlayCount = (long)gameList.Sum(g => (double)g.PlayCount),
                TotalAchievementsUnlocked = 0,
                TotalAchievementsPossible = 0
            };

            var sources = api.Database?.Sources?.Select(s => new SourceItem
            {
                Id = s.Id,
                Name = s.Name,
                IconUrl = null
            }).ToList() ?? new List<SourceItem>();

            int order = 1;
            var completionStatuses = api.Database?.CompletionStatuses?.Select(cs => new CompletionStatusItem
            {
                Id = cs.Id,
                Name = cs.Name,
                Order = order++
            }).ToList() ?? new List<CompletionStatusItem>();

            var platforms = api.Database?.Platforms?.Select(p => new PlatformEntity
            {
                Id = p.Id,
                Name = p.Name,
                SpecId = null
            }).ToList() ?? new List<PlatformEntity>();

            var genres = api.Database?.Genres?.Select(g => new NamedEntity { Id = g.Id, Name = g.Name }).ToList() ?? new List<NamedEntity>();
            var features = api.Database?.Features?.Select(f => new NamedEntity { Id = f.Id, Name = f.Name }).ToList() ?? new List<NamedEntity>();
            var tags = api.Database?.Tags?.Select(t => new NamedEntity { Id = t.Id, Name = t.Name }).ToList() ?? new List<NamedEntity>();
            var series = api.Database?.Series?.Select(s => new NamedEntity { Id = s.Id, Name = s.Name }).ToList() ?? new List<NamedEntity>();

            var activeAddons = new List<AddonDescriptor>();
            foreach (var ext in addonRegistry.RegisteredExtractors)
            {
                activeAddons.Add(new AddonDescriptor
                {
                    Id = ext.AddonKey,
                    Name = ext.DisplayName,
                    Version = "1.0.0",
                    PluginId = ext.PluginId,
                    IsEnabled = true,
                    HasData = ext.IsDataAvailable(userDataDir)
                });
            }

            return new ManifestPayload
            {
                Version = "1.0.0",
                GeneratedAtUtc = DateTime.UtcNow,
                LibrarySummary = summary,
                Sources = sources,
                CompletionStatuses = completionStatuses,
                Platforms = platforms,
                Genres = genres,
                Features = features,
                Tags = tags,
                Series = series,
                ActiveAddons = activeAddons
            };
        }

        private static List<NamedEntity> ResolveEntities<T>(
            List<Guid>? ids,
            IItemCollection<T>? collection) where T : DatabaseObject
        {
            var list = new List<NamedEntity>();
            if (ids == null || collection == null) return list;

            foreach (var id in ids)
            {
                var item = collection.Get(id);
                if (item != null)
                {
                    list.Add(new NamedEntity { Id = item.Id, Name = item.Name });
                }
            }
            return list;
        }

        private Guid GetDuplicateHiderHiddenTagId()
        {
            if (api.Database?.Tags != null)
            {
                var tag = api.Database.Tags.FirstOrDefault(t =>
                    string.Equals(t.Name, "[DH] Hidden", StringComparison.OrdinalIgnoreCase));
                if (tag != null) return tag.Id;
            }
            return Guid.Parse("db1b6850-b7ff-45fd-bde7-72b5747ec132");
        }

        public static Guid GenerateDuplicateGroupId(string name)
        {
            var clean = Regex.Replace((name ?? "").ToLowerInvariant(), @"[^a-z0-9]", "");
            if (string.IsNullOrEmpty(clean)) clean = "empty";
            using (var md5 = MD5.Create())
            {
                var hash = md5.ComputeHash(Encoding.UTF8.GetBytes(clean));
                return new Guid(hash);
            }
        }

        private (bool IsDuplicate, Guid? DuplicateGroupId, List<DuplicateCopyPayload> OtherCopies) ResolveDuplicateCopies(Game game)
        {
            var otherCopies = new List<DuplicateCopyPayload>();
            var dhHiddenTagId = GetDuplicateHiderHiddenTagId();
            bool hasDhHiddenTag = game.TagIds != null && game.TagIds.Contains(dhHiddenTagId);

            bool hasDhTag = false;
            if (game.TagIds != null && api.Database?.Tags != null)
            {
                foreach (var tagId in game.TagIds)
                {
                    var tag = api.Database.Tags.Get(tagId);
                    if (tag?.Name != null && (tag.Name.IndexOf("[DH]", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                              tag.Name.IndexOf("duplicate", StringComparison.OrdinalIgnoreCase) >= 0))
                    {
                        hasDhTag = true;
                        break;
                    }
                }
            }

            // 1. Query DuplicateHider via reflection if active in Playnite's runtime
            try
            {
                Type? dhType = null;
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                {
                    dhType = asm.GetType("DuplicateHider.DuplicateHiderPlugin");
                    if (dhType != null) break;
                }

                if (dhType != null)
                {
                    var instanceProp = dhType.GetProperty("Instance", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
                    var instance = instanceProp?.GetValue(null);
                    if (instance != null)
                    {
                        var getCopiesMethod = dhType.GetMethod("GetOtherCopies", new[] { typeof(Game) });
                        if (getCopiesMethod != null)
                        {
                            var copiesObj = getCopiesMethod.Invoke(instance, new object[] { game }) as System.Collections.IEnumerable;
                            if (copiesObj != null)
                            {
                                foreach (var item in copiesObj)
                                {
                                    if (item is Game copyGame && copyGame.Id != game.Id)
                                    {
                                        string sourceName = "Playnite";
                                        var resolvedSrc = ResolveSource(copyGame);
                                        if (resolvedSrc != null && !string.IsNullOrEmpty(resolvedSrc.Name))
                                        {
                                            sourceName = resolvedSrc.Name;
                                        }

                                        otherCopies.Add(new DuplicateCopyPayload
                                        {
                                            Id = copyGame.Id,
                                            GameId = copyGame.GameId ?? string.Empty,
                                            Name = copyGame.Name ?? string.Empty,
                                            SourceName = sourceName,
                                            IsInstalled = copyGame.IsInstalled,
                                            PlaytimeSeconds = (long)copyGame.Playtime,
                                            InstallDirectory = copyGame.InstallDirectory,
                                            Hidden = copyGame.Hidden
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Debug($"DuplicateHider reflection resolution skipped: {ex.Message}");
            }

            // 2. Fallback: match by normalized game name across database
            if (otherCopies.Count == 0 && api.Database?.Games != null)
            {
                var cleanName = (game.Name ?? "").Trim().ToLowerInvariant();
                if (cleanName.Length > 2)
                {
                    var matches = api.Database.Games
                        .Where(g => g.Id != game.Id && (g.Name ?? "").Trim().ToLowerInvariant() == cleanName)
                        .ToList();

                    foreach (var match in matches)
                    {
                        string sourceName = "Playnite";
                        var resolvedSrc = ResolveSource(match);
                        if (resolvedSrc != null && !string.IsNullOrEmpty(resolvedSrc.Name))
                        {
                            sourceName = resolvedSrc.Name;
                        }

                        otherCopies.Add(new DuplicateCopyPayload
                        {
                            Id = match.Id,
                            GameId = match.GameId ?? string.Empty,
                            Name = match.Name ?? string.Empty,
                            SourceName = sourceName,
                            IsInstalled = match.IsInstalled,
                            PlaytimeSeconds = (long)match.Playtime,
                            InstallDirectory = match.InstallDirectory,
                            Hidden = match.Hidden
                        });
                    }
                }
            }

            // Secondary copy classification:
            // A game is a secondary duplicate copy if it is Hidden AND (has [DH] tag OR another unhidden copy exists).
            // User-hidden games without other unhidden copies or DH tags remain isDuplicate = false.
            bool isDuplicate = game.Hidden && (hasDhHiddenTag || hasDhTag || otherCopies.Any(c => !c.Hidden));

            Guid? duplicateGroupId = null;
            if (isDuplicate || otherCopies.Count > 0)
            {
                duplicateGroupId = GenerateDuplicateGroupId(game.Name ?? string.Empty);
            }

            return (isDuplicate, duplicateGroupId, otherCopies);
        }

        public static string SanitizeLinkName(string? rawName, string url)
        {
            if (!string.IsNullOrWhiteSpace(rawName) &&
                !string.Equals(rawName, "Uknown", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(rawName, "Unknown", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(rawName, "Store", StringComparison.OrdinalIgnoreCase))
            {
                return rawName!.Trim();
            }

            if (string.IsNullOrWhiteSpace(url)) return "Link";

            if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
            {
                var host = uri.Host.ToLowerInvariant();
                if (host.Contains("playstation.com")) return "PlayStation Store";
                if (host.Contains("xbox.com") || host.Contains("microsoft.com")) return "Xbox Store";
                if (host.Contains("steampowered.com")) return "Steam";
                if (host.Contains("steamcommunity.com")) return "Steam Community";
                if (host.Contains("epicgames.com")) return "Epic Games Store";
                if (host.Contains("gog.com")) return "GOG";
                if (host.Contains("nintendo.com")) return "Nintendo eShop";
                if (host.Contains("ea.com") || host.Contains("origin.com")) return "EA App";
                if (host.Contains("ubisoft.com") || host.Contains("uplay.com")) return "Ubisoft Store";
                if (host.Contains("itch.io")) return "itch.io";
                if (host.Contains("pcgamingwiki.com")) return "PCGamingWiki";
                if (host.Contains("howlongtobeat.com")) return "HowLongToBeat";
            }

            return !string.IsNullOrWhiteSpace(rawName) ? rawName! : "Store";
        }

        public NamedEntity? ResolveSource(Game game)
        {
            // 1. Direct SourceId mapping
            if (game.SourceId != Guid.Empty && api.Database?.Sources != null)
            {
                var src = api.Database.Sources.Get(game.SourceId);
                if (src != null) return new NamedEntity { Id = src.Id, Name = src.Name };
            }

            // 2. Library PluginId mapping
            if (game.PluginId == Guid.Parse("cb91dfc9-b977-43bf-8e70-55f46e410fab"))
                return new NamedEntity { Id = game.PluginId, Name = "Steam" };
            if (game.PluginId == Guid.Parse("00000002-dbd1-46c6-b5d0-b1ba559d10e4"))
                return new NamedEntity { Id = game.PluginId, Name = "Epic Games" };
            if (game.PluginId == Guid.Parse("00000001-ebb2-4eec-abcb-7c89937a42bb"))
                return new NamedEntity { Id = game.PluginId, Name = "GOG" };
            if (game.PluginId == Guid.Parse("7e4fbb5e-2ae3-48d4-8ba0-6b30e7a4e287"))
                return new NamedEntity { Id = game.PluginId, Name = "Xbox" };
            if (game.PluginId == Guid.Parse("c2f038e5-8b92-4877-91f1-da9094155fc5"))
                return new NamedEntity { Id = game.PluginId, Name = "Ubisoft Connect" };
            if (game.PluginId == Guid.Parse("85dd7072-2f20-4e76-a007-41035e390724"))
                return new NamedEntity { Id = game.PluginId, Name = "EA App" };

            // 3. Platform Name Fallback (e.g., "PlayStation 5" -> "PlayStation")
            if (game.PlatformIds != null && api.Database?.Platforms != null)
            {
                var platform = game.PlatformIds
                    .Select(id => api.Database.Platforms.Get(id))
                    .FirstOrDefault(p => p != null);

                if (platform != null && !string.IsNullOrWhiteSpace(platform.Name))
                {
                    if (platform.Name.IndexOf("PlayStation", StringComparison.OrdinalIgnoreCase) >= 0)
                        return new NamedEntity { Id = platform.Id, Name = "PlayStation" };
                    if (platform.Name.IndexOf("Xbox", StringComparison.OrdinalIgnoreCase) >= 0)
                        return new NamedEntity { Id = platform.Id, Name = "Xbox" };
                    if (platform.Name.IndexOf("Nintendo", StringComparison.OrdinalIgnoreCase) >= 0)
                        return new NamedEntity { Id = platform.Id, Name = "Nintendo" };
                }
            }

            // 4. Storefront link domain inference
            if (game.Links != null)
            {
                var storeLink = game.Links.FirstOrDefault(l => !string.IsNullOrEmpty(l?.Url));
                if (storeLink != null && Uri.TryCreate(storeLink.Url, UriKind.Absolute, out var uri))
                {
                    var host = uri.Host.ToLowerInvariant();
                    if (host.Contains("playstation.com")) return new NamedEntity { Id = Guid.Empty, Name = "PlayStation" };
                    if (host.Contains("xbox.com") || host.Contains("microsoft.com")) return new NamedEntity { Id = Guid.Empty, Name = "Xbox" };
                    if (host.Contains("steampowered.com")) return new NamedEntity { Id = Guid.Empty, Name = "Steam" };
                    if (host.Contains("epicgames.com")) return new NamedEntity { Id = Guid.Empty, Name = "Epic Games" };
                    if (host.Contains("gog.com")) return new NamedEntity { Id = Guid.Empty, Name = "GOG" };
                }
            }

            return null;
        }
    }
}
