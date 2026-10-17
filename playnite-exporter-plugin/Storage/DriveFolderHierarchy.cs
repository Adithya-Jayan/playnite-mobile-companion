using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Google.Apis.Drive.v3;
using Google.Apis.Drive.v3.Data;
using Playnite.SDK;

namespace PlayniteExporterPlugin.Storage
{
    public class DriveFolderHierarchy
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly DriveService driveService;
        private readonly ConcurrentDictionary<string, string> folderIdCache = new();
        private readonly SemaphoreSlim hierarchyLock = new(1, 1);
        private string? rootFolderId;

        public DriveFolderHierarchy(DriveService driveService)
        {
            this.driveService = driveService;
        }

        public async Task<string> EnsureRootFolderAsync(string rootFolderName, CancellationToken ct = default)
        {
            if (!string.IsNullOrEmpty(rootFolderId)) return rootFolderId!;

            await hierarchyLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                if (!string.IsNullOrEmpty(rootFolderId)) return rootFolderId!;

                var query = $"name = '{EscapeQuery(rootFolderName)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
                var request = driveService.Files.List();
                request.Q = query;
                request.Fields = "files(id, name)";
                var result = await request.ExecuteAsync(ct).ConfigureAwait(false);

                if (result.Files != null && result.Files.Count > 0)
                {
                    rootFolderId = result.Files[0].Id;

                    // If multiple duplicate root folders exist, merge them
                    if (result.Files.Count > 1)
                    {
                        Logger.Warn($"Found {result.Files.Count} duplicate root folders for '{rootFolderName}'. Consolidating into canonical folder {rootFolderId}...");
                        for (int i = 1; i < result.Files.Count; i++)
                        {
                            await MergeAndDeleteDuplicateFolderAsync(rootFolderId, result.Files[i].Id, ct).ConfigureAwait(false);
                        }
                    }
                }
                else
                {
                    var folderMetadata = new File
                    {
                        Name = rootFolderName,
                        MimeType = "application/vnd.google-apps.folder"
                    };
                    var createReq = driveService.Files.Create(folderMetadata);
                    createReq.Fields = "id";
                    var created = await createReq.ExecuteAsync(ct).ConfigureAwait(false);
                    rootFolderId = created.Id;
                }

                folderIdCache[""] = rootFolderId;
                return rootFolderId;
            }
            finally
            {
                hierarchyLock.Release();
            }
        }

        public async Task<string> EnsureFolderPathAsync(string rootFolderName, string relativeDirPath, CancellationToken ct = default)
        {
            var rootId = await EnsureRootFolderAsync(rootFolderName, ct).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(relativeDirPath) || relativeDirPath == "." || relativeDirPath == "/")
            {
                return rootId;
            }

            var cleanPath = relativeDirPath.Trim('/').Replace('\\', '/');
            if (folderIdCache.TryGetValue(cleanPath, out var cachedId))
            {
                return cachedId;
            }

            await hierarchyLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                // Double-check cache after acquiring lock to prevent parallel worker duplicate folder creation
                if (folderIdCache.TryGetValue(cleanPath, out cachedId))
                {
                    return cachedId;
                }

                var segments = cleanPath.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
                var currentParentId = rootId;
                var currentPath = "";

                foreach (var segment in segments)
                {
                    currentPath = string.IsNullOrEmpty(currentPath) ? segment : $"{currentPath}/{segment}";
                    if (folderIdCache.TryGetValue(currentPath, out var segmentId))
                    {
                        currentParentId = segmentId;
                        continue;
                    }

                    var query = $"name = '{EscapeQuery(segment)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and '{currentParentId}' in parents";
                    var request = driveService.Files.List();
                    request.Q = query;
                    request.Fields = "files(id, name)";
                    var result = await request.ExecuteAsync(ct).ConfigureAwait(false);

                    if (result.Files != null && result.Files.Count > 0)
                    {
                        currentParentId = result.Files[0].Id;

                        // If parallel workers previously created duplicate folders with the same name, consolidate them
                        if (result.Files.Count > 1)
                        {
                            Logger.Warn($"Found {result.Files.Count} duplicate '{segment}' folders under parent '{currentParentId}'. Merging contents into canonical folder {currentParentId}...");
                            for (int i = 1; i < result.Files.Count; i++)
                            {
                                await MergeAndDeleteDuplicateFolderAsync(currentParentId, result.Files[i].Id, ct).ConfigureAwait(false);
                            }
                        }
                    }
                    else
                    {
                        var folderMetadata = new File
                        {
                            Name = segment,
                            MimeType = "application/vnd.google-apps.folder",
                            Parents = new List<string> { currentParentId }
                        };
                        var createReq = driveService.Files.Create(folderMetadata);
                        createReq.Fields = "id";
                        var created = await createReq.ExecuteAsync(ct).ConfigureAwait(false);
                        currentParentId = created.Id;
                    }

                    folderIdCache[currentPath] = currentParentId;
                }

                return currentParentId;
            }
            finally
            {
                hierarchyLock.Release();
            }
        }

        /// <summary>
        /// Pre-creates and warms all standard directory paths sequentially so parallel upload workers never race.
        /// Also consolidates any existing duplicate folders from previous runs.
        /// </summary>
        public async Task PreWarmHierarchyAsync(string rootFolderName, CancellationToken ct = default)
        {
            // 1. Ensure top-level parent directories first so their IDs are cached
            try
            {
                await EnsureFolderPathAsync(rootFolderName, "games", ct).ConfigureAwait(false);
                await EnsureFolderPathAsync(rootFolderName, "media", ct).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed pre-warming top-level directories.");
            }

            // 2. Concurrently verify all media subfolders in parallel
            var mediaSubPaths = new[]
            {
                "media/covers",
                "media/backgrounds",
                "media/icons",
                "media/logos",
                "media/microtrailers",
                "media/trailers"
            };

            var warmTasks = mediaSubPaths.Select(async path =>
            {
                try
                {
                    await EnsureFolderPathAsync(rootFolderName, path, ct).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Failed pre-warming directory path '{path}'.");
                }
            });

            await Task.WhenAll(warmTasks).ConfigureAwait(false);
        }

        private async Task MergeAndDeleteDuplicateFolderAsync(string canonicalFolderId, string duplicateFolderId, CancellationToken ct)
        {
            try
            {
                // 1. Move all children (files or subfolders) from duplicate folder to canonical folder
                var listReq = driveService.Files.List();
                listReq.Q = $"'{duplicateFolderId}' in parents and trashed = false";
                listReq.Fields = "files(id, name, mimeType)";
                var filesResult = await listReq.ExecuteAsync(ct).ConfigureAwait(false);

                if (filesResult.Files != null)
                {
                    foreach (var file in filesResult.Files)
                    {
                        try
                        {
                            var moveReq = driveService.Files.Update(new File(), file.Id);
                            moveReq.AddParents = canonicalFolderId;
                            moveReq.RemoveParents = duplicateFolderId;
                            moveReq.Fields = "id, parents";
                            await moveReq.ExecuteAsync(ct).ConfigureAwait(false);
                            Logger.Info($"Consolidated '{file.Name}' ({file.Id}) from duplicate folder {duplicateFolderId} to canonical {canonicalFolderId}.");
                        }
                        catch (Exception ex)
                        {
                            Logger.Warn(ex, $"Failed moving item '{file.Name}' during duplicate folder merge.");
                        }
                    }
                }

                // 2. Delete empty duplicate folder
                var delReq = driveService.Files.Delete(duplicateFolderId);
                await delReq.ExecuteAsync(ct).ConfigureAwait(false);
                Logger.Info($"Successfully removed duplicate folder {duplicateFolderId}.");
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, $"Failed consolidating duplicate folder {duplicateFolderId}.");
            }
        }

        private static string EscapeQuery(string value)
        {
            return value.Replace("\\", "\\\\").Replace("'", "\\'");
        }
    }
}
