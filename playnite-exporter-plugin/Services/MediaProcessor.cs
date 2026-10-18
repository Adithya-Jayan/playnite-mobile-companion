using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using Playnite.SDK;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Configuration;
using PlayniteExporterPlugin.Models;
using Newtonsoft.Json.Linq;

namespace PlayniteExporterPlugin.Services
{
    public class MediaProcessor
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly IPlayniteAPI api;
        private readonly ExporterSettings settings;

        public MediaProcessor(IPlayniteAPI api, ExporterSettings settings)
        {
            this.api = api;
            this.settings = settings;
        }

        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, (string Sha256, int? Width, int? Height, long SizeBytes)> MediaCache = new();

        private static (string Sha256, int? Width, int? Height, long SizeBytes) GetOrComputeMedia(string filePath, bool isImage)
        {
            var fi = new FileInfo(filePath);
            var key = $"{fi.FullName}|{fi.LastWriteTimeUtc.Ticks}|{fi.Length}";
            if (MediaCache.TryGetValue(key, out var cached))
            {
                return cached;
            }

            var hash = Sha256Hasher.ComputeFileHash(filePath);
            int? width = null;
            int? height = null;
            if (isImage)
            {
                (width, height) = GetImageDimensions(filePath);
            }
            var entry = (hash, width, height, fi.Length);
            MediaCache[key] = entry;
            return entry;
        }

        public async Task<(GameMediaContainer Media, List<PlannedUpload> MediaUploads)> ResolveGameMediaAsync(
            Game game,
            string userDataDir)
        {
            await Task.Yield();
            var container = new GameMediaContainer();
            var uploads = new List<PlannedUpload>();

            // 1. Cover Image
            if (settings.SyncCovers && !string.IsNullOrEmpty(game.CoverImage))
            {
                var coverPath = api.Database.GetFullFilePath(game.CoverImage);
                if (File.Exists(coverPath))
                {
                    try
                    {
                        var ext = Path.GetExtension(coverPath).TrimStart('.').ToLowerInvariant();
                        if (string.IsNullOrEmpty(ext)) ext = "jpg";
                        var (hash, width, height, length) = GetOrComputeMedia(coverPath, isImage: true);
                        var relPath = $"media/covers/{hash}.{ext}";

                        container.Cover = new MediaImagePointer
                        {
                            RelativePath = relPath,
                            Sha256 = hash,
                            Format = ext == "jpeg" ? "jpg" : ext,
                            Width = width,
                            Height = height
                        };

                        uploads.Add(new PlannedUpload(
                            relPath,
                            string.Empty,
                            hash,
                            length,
                            "cover",
                            game.Id,
                            existingDriveFileId: null,
                            mimeType: GetMimeType(ext),
                            sourceFilePath: coverPath
                        ));
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, $"Failed resolving cover image for {game.Name}");
                    }
                }
            }

            // 2. Background Image
            if (settings.SyncBackgrounds && !string.IsNullOrEmpty(game.BackgroundImage))
            {
                var bgPath = api.Database.GetFullFilePath(game.BackgroundImage);
                if (File.Exists(bgPath))
                {
                    try
                    {
                        var ext = Path.GetExtension(bgPath).TrimStart('.').ToLowerInvariant();
                        if (string.IsNullOrEmpty(ext)) ext = "jpg";
                        var (hash, width, height, length) = GetOrComputeMedia(bgPath, isImage: true);
                        var relPath = $"media/backgrounds/{hash}.{ext}";

                        container.Background = new MediaImagePointer
                        {
                            RelativePath = relPath,
                            Sha256 = hash,
                            Format = ext == "jpeg" ? "jpg" : ext,
                            Width = width,
                            Height = height
                        };

                        uploads.Add(new PlannedUpload(
                            relPath,
                            string.Empty,
                            hash,
                            length,
                            "background",
                            game.Id,
                            existingDriveFileId: null,
                            mimeType: GetMimeType(ext),
                            sourceFilePath: bgPath
                        ));
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, $"Failed resolving background image for {game.Name}");
                    }
                }
            }

            // 3. Icon
            if (!string.IsNullOrEmpty(game.Icon))
            {
                var iconPath = api.Database.GetFullFilePath(game.Icon);
                if (File.Exists(iconPath))
                {
                    try
                    {
                        var ext = Path.GetExtension(iconPath).TrimStart('.').ToLowerInvariant();
                        if (string.IsNullOrEmpty(ext)) ext = "png";
                        var (hash, width, height, length) = GetOrComputeMedia(iconPath, isImage: true);
                        var relPath = $"media/icons/{hash}.{ext}";

                        container.Icon = new MediaImagePointer
                        {
                            RelativePath = relPath,
                            Sha256 = hash,
                            Format = ext,
                            Width = width,
                            Height = height
                        };

                        uploads.Add(new PlannedUpload(
                            relPath,
                            string.Empty,
                            hash,
                            length,
                            "icon",
                            game.Id,
                            existingDriveFileId: null,
                            mimeType: GetMimeType(ext),
                            sourceFilePath: iconPath
                        ));
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, $"Failed resolving icon for {game.Name}");
                    }
                }
            }

            // 4. ExtraMetadata Assets (Logo, Microtrailer, Trailer)
            var extraMetaDir = Path.Combine(userDataDir, "ExtraMetadata", "games", game.Id.ToString());
            if (Directory.Exists(extraMetaDir))
            {
                // Logo
                if (settings.SyncLogos)
                {
                    var logoPath = Path.Combine(extraMetaDir, "Logo.png");
                    if (File.Exists(logoPath))
                    {
                        try
                        {
                            var (hash, width, height, length) = GetOrComputeMedia(logoPath, isImage: true);
                            var relPath = $"media/logos/{game.Id}.png";

                            container.Logo = new MediaImagePointer
                            {
                                RelativePath = relPath,
                                Sha256 = hash,
                                Format = "png",
                                Width = width,
                                Height = height
                            };

                            uploads.Add(new PlannedUpload(
                                relPath,
                                string.Empty,
                                hash,
                                length,
                                "logo",
                                game.Id,
                                existingDriveFileId: null,
                                mimeType: "image/png",
                                sourceFilePath: logoPath
                            ));
                        }
                        catch (Exception ex)
                        {
                            Logger.Warn(ex, $"Failed resolving logo for {game.Name}");
                        }
                    }
                }

                // Microtrailer
                if (settings.SyncMicrotrailers)
                {
                    var microtrailerPath = Path.Combine(extraMetaDir, "VideoMicrotrailer.mp4");
                    if (File.Exists(microtrailerPath))
                    {
                        try
                        {
                            var (hash, _, _, length) = GetOrComputeMedia(microtrailerPath, isImage: false);
                            var relPath = $"media/microtrailers/{game.Id}.mp4";

                            container.Microtrailer = new MediaVideoPointer
                            {
                                RelativePath = relPath,
                                Sha256 = hash,
                                SizeBytes = length,
                                DurationSeconds = 6.0
                            };

                            uploads.Add(new PlannedUpload(
                                relPath,
                                string.Empty,
                                hash,
                                length,
                                "microtrailer",
                                game.Id,
                                existingDriveFileId: null,
                                mimeType: "video/mp4",
                                sourceFilePath: microtrailerPath
                            ));
                        }
                        catch (Exception ex)
                        {
                            Logger.Warn(ex, $"Failed resolving microtrailer for {game.Name}");
                        }
                    }
                }

                // Trailer
                if (settings.SyncTrailers)
                {
                    var trailerPath = Path.Combine(extraMetaDir, "VideoTrailer.mp4");
                    if (File.Exists(trailerPath))
                    {
                        try
                        {
                            var (hash, _, _, length) = GetOrComputeMedia(trailerPath, isImage: false);
                            var relPath = $"media/trailers/{game.Id}.mp4";

                            container.Trailer = new MediaTrailerPointer
                            {
                                RelativePath = relPath,
                                Sha256 = hash,
                                SizeBytes = length,
                                DurationSeconds = null,
                                WebUrl = null
                            };

                            uploads.Add(new PlannedUpload(
                                relPath,
                                string.Empty,
                                hash,
                                length,
                                "trailer",
                                game.Id,
                                existingDriveFileId: null,
                                mimeType: "video/mp4",
                                sourceFilePath: trailerPath
                            ));
                        }
                        catch (Exception ex)
                        {
                            Logger.Warn(ex, $"Failed resolving trailer for {game.Name}");
                        }
                    }
                }
            }

            // 5. Fallback: Stream trailer directly from Steam CDN if ExtraMetadata cached SteamAppDetails
            if (container.Trailer == null)
            {
                var steamTrailerUrl = TryGetSteamTrailerUrl(userDataDir, game.Id);
                if (!string.IsNullOrEmpty(steamTrailerUrl))
                {
                    container.Trailer = new MediaTrailerPointer
                    {
                        RelativePath = null,
                        Sha256 = null,
                        SizeBytes = null,
                        DurationSeconds = null,
                        WebUrl = steamTrailerUrl
                    };
                }
            }

            return (container, uploads);
        }

        private static string? TryGetSteamTrailerUrl(string userDataDir, Guid gameId)
        {
            try
            {
                var appDetailsPath = Path.Combine(
                    userDataDir,
                    "ExtensionsData",
                    "705fdbca-e1fc-4004-b839-1d040b8b4429",
                    $"{gameId}_SteamAppDetails.json"
                );
                if (!File.Exists(appDetailsPath)) return null;

                var json = File.ReadAllText(appDetailsPath);
                var root = JObject.Parse(json);
                var movies = root["movies"] as JArray ?? root["data"]?["movies"] as JArray;
                if (movies == null || movies.Count == 0) return null;

                var firstMovie = movies[0];
                var mp4Obj = firstMovie["mp4"] as JObject;
                var url = mp4Obj?["480"]?.ToString() ?? mp4Obj?["max"]?.ToString();
                if (string.IsNullOrEmpty(url))
                {
                    var webmObj = firstMovie["webm"] as JObject;
                    url = webmObj?["480"]?.ToString() ?? webmObj?["max"]?.ToString();
                }

                if (!string.IsNullOrEmpty(url))
                {
                    if (url!.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
                    {
                        url = "https://" + url.Substring(7);
                    }
                    return url;
                }
            }
            catch (Exception ex)
            {
                Logger.Debug(ex, $"Failed parsing Steam trailer stream for game {gameId}");
            }
            return null;
        }

        private static (int? Width, int? Height) GetImageDimensions(string filePath)
        {
            try
            {
                using var img = System.Drawing.Image.FromFile(filePath);
                return (img.Width, img.Height);
            }
            catch
            {
                return (null, null);
            }
        }

        private static string GetMimeType(string extension)
        {
            return extension.ToLowerInvariant() switch
            {
                "webp" => "image/webp",
                "png" => "image/png",
                "ico" => "image/x-icon",
                "jpg" or "jpeg" => "image/jpeg",
                "mp4" => "video/mp4",
                _ => "application/octet-stream"
            };
        }
    }
}
