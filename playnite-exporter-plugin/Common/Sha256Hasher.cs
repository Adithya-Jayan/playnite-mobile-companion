using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace PlayniteExporterPlugin.Common
{
    public static class Sha256Hasher
    {
        public static string ComputeStringHash(string content)
        {
            if (content == null) throw new ArgumentNullException(nameof(content));
            using var sha256 = SHA256.Create();
            var bytes = Encoding.UTF8.GetBytes(content);
            var hash = sha256.ComputeHash(bytes);
            return ToHex(hash);
        }

        public static string ComputeFileHash(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath)) throw new ArgumentNullException(nameof(filePath));
            if (!File.Exists(filePath)) throw new FileNotFoundException("File not found for hash calculation", filePath);

            using var sha256 = SHA256.Create();
            using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var hash = sha256.ComputeHash(stream);
            return ToHex(hash);
        }

        public static string ComputeStreamHash(Stream stream)
        {
            if (stream == null) throw new ArgumentNullException(nameof(stream));
            using var sha256 = SHA256.Create();
            var hash = sha256.ComputeHash(stream);
            return ToHex(hash);
        }

        private static string ToHex(byte[] bytes)
        {
            var sb = new StringBuilder(bytes.Length * 2);
            for (int i = 0; i < bytes.Length; i++)
            {
                sb.Append(bytes[i].ToString("x2"));
            }
            return sb.ToString();
        }
    }
}
