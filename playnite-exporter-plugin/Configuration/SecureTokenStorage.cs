using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace PlayniteExporterPlugin.Configuration
{
    public class SecureTokenStorage
    {
        private readonly string tokenFilePath;

        public SecureTokenStorage(string pluginUserDataDir)
        {
            if (!Directory.Exists(pluginUserDataDir))
            {
                Directory.CreateDirectory(pluginUserDataDir);
            }
            tokenFilePath = Path.Combine(pluginUserDataDir, "drive_auth.dat");
        }

        public void SaveEncryptedToken(string tokenJson)
        {
            if (string.IsNullOrEmpty(tokenJson))
            {
                DeleteToken();
                return;
            }

            var plainBytes = Encoding.UTF8.GetBytes(tokenJson);
            var encryptedBytes = ProtectedData.Protect(
                plainBytes,
                optionalEntropy: null,
                DataProtectionScope.CurrentUser
            );
            File.WriteAllBytes(tokenFilePath, encryptedBytes);
        }

        public string? LoadDecryptedToken()
        {
            if (!File.Exists(tokenFilePath)) return null;

            try
            {
                var encryptedBytes = File.ReadAllBytes(tokenFilePath);
                var plainBytes = ProtectedData.Unprotect(
                    encryptedBytes,
                    optionalEntropy: null,
                    DataProtectionScope.CurrentUser
                );
                return Encoding.UTF8.GetString(plainBytes);
            }
            catch
            {
                return null;
            }
        }

        public void DeleteToken()
        {
            if (File.Exists(tokenFilePath))
            {
                try
                {
                    File.Delete(tokenFilePath);
                }
                catch { }
            }
        }

        public bool HasToken()
        {
            return File.Exists(tokenFilePath);
        }
    }
}
