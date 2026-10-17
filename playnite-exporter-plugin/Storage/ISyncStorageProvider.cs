using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace PlayniteExporterPlugin.Storage
{
    public interface ISyncStorageProvider
    {
        string ProviderName { get; }

        bool IsAuthenticated { get; }

        Task InitializeAsync(CancellationToken ct = default);

        Task<string> UploadFileAsync(
            string relativePath,
            string mimeType,
            Stream stream,
            string? existingFileId = null,
            IProgress<long>? progress = null,
            CancellationToken ct = default);

        Task<bool> FileExistsAsync(string relativePath, CancellationToken ct = default);

        Task<Stream?> DownloadFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default);

        Task DeleteFileAsync(string relativePath, string? fileId = null, CancellationToken ct = default);

        Task<string?> GetFileIdAsync(string relativePath, CancellationToken ct = default);
    }
}
