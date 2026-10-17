using System;
using System.Collections.Generic;
using System.Linq;
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
            NamedEntity? source = null;
            if (game.SourceId != Guid.Empty && api.Database?.Sources != null)
            {
                var s = api.Database.Sources.Get(game.SourceId);
                if (s != null) source = new NamedEntity { Id = s.Id, Name = s.Name };
            }

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
                        links.Add(new LinkEntity { Name = link.Name ?? string.Empty, Url = link.Url });
                    }
                }
            }

            // Media
            var (media, mediaUploads) = await mediaProcessor.ResolveGameMediaAsync(game, userDataDir);

            // Addons
            var addons = await addonRegistry.ExtractAllAsync(game, userDataDir);

            // Duplicate copies & DuplicateHider resolution
            var (isDuplicate, otherCopies) = ResolveDuplicateCopies(game);

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

        private static readonly Guid DuplicateHiderHiddenTagId = Guid.Parse("db1b6850-b7ff-45fd-bde7-72b5747ec132");
        private static readonly Guid DuplicateHiderRevealedTagId = Guid.Parse("4584ccb9-1a4a-48b1-a1c7-4921bbcceaf8");

        private (bool IsDuplicate, List<DuplicateCopyPayload> OtherCopies) ResolveDuplicateCopies(Game game)
        {
            var otherCopies = new List<DuplicateCopyPayload>();
            bool isDuplicate = false;

            // 1. Check DuplicateHider plugin's standard hidden tag ID
            if (game.TagIds != null && game.TagIds.Contains(DuplicateHiderHiddenTagId))
            {
                isDuplicate = true;
            }

            // 2. Query DuplicateHider via reflection if active in Playnite's runtime
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
                                        if (copyGame.SourceId != Guid.Empty && api.Database?.Sources != null)
                                        {
                                            var s = api.Database.Sources.Get(copyGame.SourceId);
                                            if (s != null) sourceName = s.Name ?? "Playnite";
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

                                        if (game.Hidden && !copyGame.Hidden)
                                        {
                                            isDuplicate = true;
                                        }
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

            // 3. Fallback: match by normalized game name across database
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
                        if (match.SourceId != Guid.Empty && api.Database.Sources != null)
                        {
                            var s = api.Database.Sources.Get(match.SourceId);
                            if (s != null) sourceName = s.Name ?? "Playnite";
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

                        if (game.Hidden && !match.Hidden)
                        {
                            isDuplicate = true;
                        }
                    }
                }
            }

            return (isDuplicate, otherCopies);
        }
    }
}
