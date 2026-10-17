using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace PlayniteExporterPlugin.Storage
{
    public class LocalFolderSyncProvider : ISyncStorageProvider
    {
        private readonly string rootDirectory;

        public string ProviderName => "LocalFolder";
        public string RootDirectory => rootDirectory;

        public bool IsAuthenticated
        {
            get
            {
                if (string.IsNullOrWhiteSpace(rootDirectory)) return false;
                try
                {
                    var root = Path.GetPathRoot(rootDirectory);
                    if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return false;
                    return true;
                }
                catch
                {
                    return false;
                }
            }
        }

        public LocalFolderSyncProvider(string rootDirectory)
        {
            if (string.IsNullOrWhiteSpace(rootDirectory))
            {
                throw new ArgumentException("Root directory cannot be null or empty", nameof(rootDirectory));
            }
            this.rootDirectory = Path.GetFullPath(rootDirectory);
        }

        public Task InitializeAsync(CancellationToken ct = default)
        {
            if (!Directory.Exists(rootDirectory))
            {
                Directory.CreateDirectory(rootDirectory);
            }
            return Task.CompletedTask;
        }

        public async Task<string> UploadFileAsync(
            string relativePath,
            string mimeType,
            Stream stream,
            string? existingFileId = null,
            IProgress<long>? progress = null,
            CancellationToken ct = default)
        {
            var normalizedPath = relativePath.Replace('/', Path.DirectorySeparatorChar);
            var targetPath = Path.Combine(rootDirectory, normalizedPath);
            var parentDir = Path.GetDirectoryName(targetPath);
            if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
            {
                Directory.CreateDirectory(parentDir);
            }

            // Atomic file write using temporary file
            var tempPath = targetPath + $".tmp_{Guid.NewGuid():N}";
            try
            {
                using (var dest = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true))
                {
                    var buffer = new byte[81920];
                    int read;
                    long totalBytes = 0;
                    while ((read = await stream.ReadAsync(buffer, 0, buffer.Length, ct)) > 0)
                    {
                        await dest.WriteAsync(buffer, 0, read, ct);
                        totalBytes += read;
                        progress?.Report(totalBytes);
                    }
                }

                if (File.Exists(targetPath))
                {
                    File.Delete(targetPath);
                }
                File.Move(tempPath, targetPath);
            }
            finally
            {
                if (File.Exists(tempPath))
                {
                    try { File.Delete(tempPath); } catch { }
                }
            }

            return relativePath;
        }

        public Task<bool> FileExistsAsync(string relativePath, CancellationToken ct = default)
        {
            var normalizedPath = relativePath.Replace('/', Path.DirectorySeparatorChar);
            var targetPath = Path.Combine(rootDirectory, normalizedPath);
            return Task.FromResult(File.Exists(targetPath));
        }

        public Task<Stream?> DownloadFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default)
        {
            var targetRel = !string.IsNullOrEmpty(fileId) ? fileId! : relativePath;
            var normalizedPath = targetRel.Replace('/', Path.DirectorySeparatorChar);
            var targetPath = Path.Combine(rootDirectory, normalizedPath);

            if (!File.Exists(targetPath))
            {
                return Task.FromResult<Stream?>(null);
            }

            var stream = new FileStream(targetPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            return Task.FromResult<Stream?>(stream);
        }

        public Task DeleteFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default)
        {
            var targetRel = !string.IsNullOrEmpty(fileId) ? fileId! : relativePath;
            var normalizedPath = targetRel.Replace('/', Path.DirectorySeparatorChar);
            var targetPath = Path.Combine(rootDirectory, normalizedPath);

            if (File.Exists(targetPath))
            {
                try
                {
                    File.Delete(targetPath);
                }
                catch { }
            }

            return Task.CompletedTask;
        }

        public Task<string?> GetFileIdAsync(string relativePath, CancellationToken ct = default)
        {
            var normalizedPath = relativePath.Replace('/', Path.DirectorySeparatorChar);
            var targetPath = Path.Combine(rootDirectory, normalizedPath);
            return Task.FromResult(File.Exists(targetPath) ? relativePath : null);
        }
    }
}
