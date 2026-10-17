using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Google;
using Google.Apis.Drive.v3;
using Google.Apis.Drive.v3.Data;
using Google.Apis.Upload;
using Playnite.SDK;
using PlayniteExporterPlugin.Configuration;
using Polly;
using Polly.Retry;

namespace PlayniteExporterPlugin.Storage
{
    public class GoogleDriveSyncProvider : ISyncStorageProvider
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly GoogleAuthService authService;
        private readonly ExporterSettings settings;
        private DriveService? driveService;
        private DriveFolderHierarchy? folderHierarchy;
        private readonly AsyncRetryPolicy retryPolicy;
        private static readonly Random Rnd = new();

        public string ProviderName => "GoogleDrive";

        public bool IsAuthenticated => authService.IsAuthenticated;

        public GoogleDriveSyncProvider(GoogleAuthService authService, ExporterSettings settings)
        {
            this.authService = authService;
            this.settings = settings;

            retryPolicy = Policy
                .Handle<GoogleApiException>(ex =>
                    ex.HttpStatusCode == (HttpStatusCode)429 ||
                    (int)ex.HttpStatusCode >= 500 ||
                    (ex.HttpStatusCode == HttpStatusCode.Forbidden &&
                        (!string.IsNullOrEmpty(ex.Message) &&
                         (ex.Message.IndexOf("rateLimitExceeded", StringComparison.OrdinalIgnoreCase) >= 0 ||
                          ex.Message.IndexOf("userRateLimitExceeded", StringComparison.OrdinalIgnoreCase) >= 0 ||
                          ex.Message.IndexOf("quotaExceeded", StringComparison.OrdinalIgnoreCase) >= 0))))
                .Or<HttpRequestException>()
                .Or<IOException>()
                .WaitAndRetryAsync(
                    retryCount: 5,
                    sleepDurationProvider: retryAttempt =>
                    {
                        var baseDelay = TimeSpan.FromSeconds(Math.Pow(2, retryAttempt));
                        var jitter = TimeSpan.FromMilliseconds(Rnd.Next(0, 1000));
                        return baseDelay + jitter;
                    },
                    onRetry: (exception, timespan, retryCount, context) =>
                    {
                        Logger.Warn($"Google Drive API throttle/failure. Retrying {retryCount}/5 after {timespan.TotalSeconds:N1}s. Error: {exception.Message}");
                    }
                );
        }

        public async Task InitializeAsync(CancellationToken ct = default)
        {
            if (!authService.IsAuthenticated)
            {
                throw new InvalidOperationException("Google Drive authentication required. Please connect your Google account in Extension Settings or select Local Folder Sync.");
            }

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(60));
            var effectiveCt = timeoutCts.Token;

            try
            {
                driveService = await authService.CreateDriveServiceAsync(effectiveCt).ConfigureAwait(false);
                folderHierarchy = new DriveFolderHierarchy(driveService);
                var rootName = !string.IsNullOrWhiteSpace(settings.GoogleDriveFolderName)
                    ? settings.GoogleDriveFolderName
                    : "PlayniteSync";
                var rootId = await folderHierarchy.EnsureRootFolderAsync(rootName, effectiveCt).ConfigureAwait(false);
                settings.GoogleDriveFolderId = rootId;
                await folderHierarchy.PreWarmHierarchyAsync(rootName, effectiveCt).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested && timeoutCts.IsCancellationRequested)
            {
                throw new TimeoutException("Google Drive initialization timed out after 60 seconds. Please check your network connection and Google Drive settings.");
            }
        }

        public async Task<string> UploadFileAsync(
            string relativePath,
            string mimeType,
            Stream stream,
            string? existingFileId = null,
            IProgress<long>? progress = null,
            CancellationToken ct = default)
        {
            if (driveService == null || folderHierarchy == null)
            {
                await InitializeAsync(ct).ConfigureAwait(false);
            }

            var cleanPath = relativePath.Trim('/').Replace('\\', '/');
            var dirName = Path.GetDirectoryName(cleanPath)?.Replace('\\', '/') ?? "";
            var fileName = Path.GetFileName(cleanPath);

            var rootName = !string.IsNullOrWhiteSpace(settings.GoogleDriveFolderName)
                ? settings.GoogleDriveFolderName
                : "PlayniteSync";
            var parentFolderId = await folderHierarchy!.EnsureFolderPathAsync(rootName, dirName, ct).ConfigureAwait(false);

            return await retryPolicy.ExecuteAsync(async () =>
            {
                if (stream.CanSeek)
                {
                    stream.Position = 0;
                }

                var fileMetadata = new Google.Apis.Drive.v3.Data.File
                {
                    Name = fileName,
                    MimeType = mimeType
                };

                if (!string.IsNullOrEmpty(existingFileId))
                {
                    try
                    {
                        var updateReq = driveService!.Files.Update(fileMetadata, existingFileId, stream, mimeType);
                        updateReq.Fields = "id"; // Only request 'id' to avoid server responsePreparationFailure
                        if (progress != null)
                        {
                            updateReq.ProgressChanged += p =>
                            {
                                if (p.Status == UploadStatus.Uploading)
                                {
                                    progress.Report(p.BytesSent);
                                }
                            };
                        }
                        var uploadResult = await updateReq.UploadAsync(ct).ConfigureAwait(false);
                        if (uploadResult.Status == UploadStatus.Failed)
                        {
                            if (IsResponsePreparationSuccess(uploadResult.Exception))
                            {
                                var recoveredId = await FindExistingFileIdInFolderAsync(parentFolderId, fileName, ct).ConfigureAwait(false);
                                if (!string.IsNullOrEmpty(recoveredId))
                                {
                                    Logger.Warn($"Google Drive update returned responsePreparationFailure for '{fileName}', but confirmed operation succeeded. Recovered file ID: {recoveredId}");
                                    return recoveredId!;
                                }
                                return existingFileId!;
                            }

                            if (uploadResult.Exception is GoogleApiException gEx &&
                                (gEx.HttpStatusCode == HttpStatusCode.Gone || gEx.HttpStatusCode == HttpStatusCode.NotFound))
                            {
                                Logger.Warn($"Target file ID '{existingFileId}' for '{fileName}' is Gone/NotFound. Falling back to fresh creation.");
                                return await CreateFreshFileAsync(parentFolderId, fileMetadata, stream, mimeType, progress, ct).ConfigureAwait(false);
                            }

                            throw uploadResult.Exception ?? new InvalidOperationException($"Upload failed for {fileName}");
                        }
                        return updateReq.ResponseBody?.Id ?? existingFileId!;
                    }
                    catch (GoogleApiException ex) when (ex.HttpStatusCode == HttpStatusCode.Gone || ex.HttpStatusCode == HttpStatusCode.NotFound)
                    {
                        Logger.Warn($"Target file ID '{existingFileId}' for '{fileName}' threw {ex.HttpStatusCode}. Falling back to fresh creation.");
                        return await CreateFreshFileAsync(parentFolderId, fileMetadata, stream, mimeType, progress, ct).ConfigureAwait(false);
                    }
                }
                else
                {
                    return await CreateFreshFileAsync(parentFolderId, fileMetadata, stream, mimeType, progress, ct).ConfigureAwait(false);
                }
            }).ConfigureAwait(false);
        }

        private async Task<string> CreateFreshFileAsync(
            string parentFolderId,
            Google.Apis.Drive.v3.Data.File fileMetadata,
            Stream stream,
            string mimeType,
            IProgress<long>? progress,
            CancellationToken ct)
        {
            if (stream.CanSeek)
            {
                stream.Position = 0;
            }

            fileMetadata.Parents = new List<string> { parentFolderId };
            var createReq = driveService!.Files.Create(fileMetadata, stream, mimeType);
            createReq.Fields = "id"; // Only request 'id' to avoid server responsePreparationFailure
            if (progress != null)
            {
                createReq.ProgressChanged += p =>
                {
                    if (p.Status == UploadStatus.Uploading)
                    {
                        progress.Report(p.BytesSent);
                    }
                };
            }
            var uploadResult = await createReq.UploadAsync(ct).ConfigureAwait(false);
            if (uploadResult.Status == UploadStatus.Failed)
            {
                if (IsResponsePreparationSuccess(uploadResult.Exception))
                {
                    var recoveredId = await FindExistingFileIdInFolderAsync(parentFolderId, fileMetadata.Name, ct).ConfigureAwait(false);
                    if (!string.IsNullOrEmpty(recoveredId))
                    {
                        Logger.Warn($"Google Drive create returned responsePreparationFailure for '{fileMetadata.Name}', but confirmed operation succeeded. Recovered file ID: {recoveredId}");
                        return recoveredId!;
                    }
                }

                throw uploadResult.Exception ?? new InvalidOperationException($"Upload failed for {fileMetadata.Name}");
            }
            return createReq.ResponseBody?.Id ?? throw new InvalidOperationException($"Did not receive ID for created file {fileMetadata.Name}");
        }

        private static bool IsResponsePreparationSuccess(Exception? ex)
        {
            if (ex == null) return false;
            var msg = ex.Message ?? "";
            if (msg.IndexOf("The operation was successful", StringComparison.OrdinalIgnoreCase) >= 0 ||
                msg.IndexOf("responsePreparationFailure", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return true;
            }
            if (ex.InnerException != null)
            {
                return IsResponsePreparationSuccess(ex.InnerException);
            }
            return false;
        }

        private async Task<string?> FindExistingFileIdInFolderAsync(string parentFolderId, string fileName, CancellationToken ct)
        {
            try
            {
                var escapedName = fileName.Replace("\\", "\\\\").Replace("'", "\\'");
                var query = $"name = '{escapedName}' and '{parentFolderId}' in parents and trashed = false";
                var listReq = driveService!.Files.List();
                listReq.Q = query;
                listReq.Fields = "files(id, name)";
                var res = await listReq.ExecuteAsync(ct).ConfigureAwait(false);
                if (res.Files != null && res.Files.Count > 0)
                {
                    return res.Files[0].Id;
                }
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, $"Failed searching for '{fileName}' in parent folder {parentFolderId}");
            }
            return null;
        }

        public async Task<bool> FileExistsAsync(string relativePath, CancellationToken ct = default)
        {
            var id = await GetFileIdAsync(relativePath, ct).ConfigureAwait(false);
            return !string.IsNullOrEmpty(id);
        }

        public async Task<Stream?> DownloadFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default)
        {
            if (driveService == null)
            {
                await InitializeAsync(ct).ConfigureAwait(false);
            }

            var targetId = fileId;
            if (string.IsNullOrEmpty(targetId))
            {
                targetId = await GetFileIdAsync(relativePath, ct).ConfigureAwait(false);
            }

            if (string.IsNullOrEmpty(targetId))
            {
                return null;
            }

            var ms = new MemoryStream();
            await retryPolicy.ExecuteAsync(async () =>
            {
                var getReq = driveService!.Files.Get(targetId);
                await getReq.DownloadAsync(ms, ct).ConfigureAwait(false);
            }).ConfigureAwait(false);

            ms.Position = 0;
            return ms;
        }

        public async Task DeleteFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default)
        {
            if (driveService == null)
            {
                await InitializeAsync(ct).ConfigureAwait(false);
            }

            var targetId = fileId;
            if (string.IsNullOrEmpty(targetId))
            {
                targetId = await GetFileIdAsync(relativePath, ct).ConfigureAwait(false);
            }

            if (!string.IsNullOrEmpty(targetId))
            {
                await retryPolicy.ExecuteAsync(async () =>
                {
                    try
                    {
                        var delReq = driveService!.Files.Delete(targetId);
                        await delReq.ExecuteAsync(ct).ConfigureAwait(false);
                    }
                    catch (GoogleApiException ex) when (ex.HttpStatusCode == HttpStatusCode.NotFound || ex.HttpStatusCode == HttpStatusCode.Gone)
                    {
                        // File already gone or trashed - treat as success
                    }
                }).ConfigureAwait(false);
            }
        }

        public async Task<string?> GetFileIdAsync(string relativePath, CancellationToken ct = default)
        {
            if (driveService == null || folderHierarchy == null)
            {
                await InitializeAsync(ct).ConfigureAwait(false);
            }

            var cleanPath = relativePath.Trim('/').Replace('\\', '/');
            var dirName = Path.GetDirectoryName(cleanPath)?.Replace('\\', '/') ?? "";
            var fileName = Path.GetFileName(cleanPath);

            var rootName = !string.IsNullOrWhiteSpace(settings.GoogleDriveFolderName)
                ? settings.GoogleDriveFolderName
                : "PlayniteSync";
            var parentFolderId = await folderHierarchy!.EnsureFolderPathAsync(rootName, dirName, ct).ConfigureAwait(false);

            return await retryPolicy.ExecuteAsync(async () =>
            {
                var query = $"name = '{fileName.Replace("'", "\\'")}' and '{parentFolderId}' in parents and trashed = false";
                var listReq = driveService!.Files.List();
                listReq.Q = query;
                listReq.Fields = "files(id, name)";
                var res = await listReq.ExecuteAsync(ct).ConfigureAwait(false);
                if (res.Files != null && res.Files.Count > 0)
                {
                    return res.Files[0].Id;
                }
                return null;
            }).ConfigureAwait(false);
        }
    }
}
