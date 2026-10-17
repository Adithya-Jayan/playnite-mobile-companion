using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Auth.OAuth2.Flows;
using Google.Apis.Auth.OAuth2.Responses;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using Newtonsoft.Json;
using Playnite.SDK;
using PlayniteExporterPlugin.Configuration;

namespace PlayniteExporterPlugin.Storage
{
    public class GoogleAuthService
    {
        private static readonly ILogger Logger = LogManager.GetLogger();
        private readonly ExporterSettings settings;
        private readonly SecureTokenStorage tokenStorage;
        private UserCredential? credential;

        public const string LoopbackPort = "51734";
        public const string DefaultRedirectUri = "http://127.0.0.1:51734/callback";

        public GoogleAuthService(ExporterSettings settings, string pluginUserDataDir)
        {
            this.settings = settings;
            this.tokenStorage = new SecureTokenStorage(pluginUserDataDir);
        }

        public bool CheckStoredCredentials()
        {
            if (!tokenStorage.HasToken())
            {
                return false;
            }

            try
            {
                var decrypted = tokenStorage.LoadDecryptedToken();
                if (string.IsNullOrWhiteSpace(decrypted))
                {
                    return false;
                }

                var token = JsonConvert.DeserializeObject<TokenResponse>(decrypted!);
                return token != null && (!string.IsNullOrWhiteSpace(token.RefreshToken) || !string.IsNullOrWhiteSpace(token.AccessToken));
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed inspecting stored DPAPI credentials.");
                return false;
            }
        }

        public string GetConnectedAccountInfo()
        {
            if (!IsAuthenticated)
            {
                return string.Empty;
            }

            try
            {
                var decryptedToken = tokenStorage.LoadDecryptedToken();
                if (!string.IsNullOrEmpty(decryptedToken))
                {
                    var token = JsonConvert.DeserializeObject<TokenResponse>(decryptedToken!);
                    if (!string.IsNullOrEmpty(token?.IdToken))
                    {
                        var parts = token!.IdToken.Split('.');
                        if (parts.Length >= 2)
                        {
                            string payload = parts[1];
                            payload = payload.Replace('-', '+').Replace('_', '/');
                            switch (payload.Length % 4)
                            {
                                case 2: payload += "=="; break;
                                case 3: payload += "="; break;
                            }
                            var jsonBytes = Convert.FromBase64String(payload);
                            var json = System.Text.Encoding.UTF8.GetString(jsonBytes);
                            var dict = JsonConvert.DeserializeObject<System.Collections.Generic.Dictionary<string, object>>(json);
                            if (dict != null && dict.TryGetValue("email", out var emailObj) && emailObj != null)
                            {
                                var emailStr = emailObj.ToString();
                                if (!string.IsNullOrWhiteSpace(emailStr))
                                {
                                    return emailStr;
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed to parse account email from Google Drive token.");
            }

            return !string.IsNullOrWhiteSpace(settings.GoogleDriveFolderName)
                ? settings.GoogleDriveFolderName
                : "PlayniteSync";
        }

        public string? GetMobilePairingPayload()
        {
            if (!IsAuthenticated)
            {
                return null;
            }

            try
            {
                var decrypted = tokenStorage.LoadDecryptedToken();
                if (string.IsNullOrEmpty(decrypted))
                {
                    return null;
                }

                var token = JsonConvert.DeserializeObject<TokenResponse>(decrypted!);
                if (token == null)
                {
                    return null;
                }

                var payload = new
                {
                    clientId = settings.GoogleClientId?.Trim() ?? string.Empty,
                    clientSecret = settings.GoogleClientSecret?.Trim() ?? string.Empty,
                    refreshToken = token.RefreshToken ?? string.Empty,
                    accessToken = token.AccessToken ?? string.Empty,
                    folderName = string.IsNullOrWhiteSpace(settings.GoogleDriveFolderName) ? "PlayniteSync" : settings.GoogleDriveFolderName.Trim()
                };

                var json = JsonConvert.SerializeObject(payload);
                var bytes = System.Text.Encoding.UTF8.GetBytes(json);
                return "playnite://" + Convert.ToBase64String(bytes);
            }
            catch (Exception ex)
            {
                Logger.Warn(ex, "Failed generating mobile pairing payload.");
                return null;
            }
        }

        public bool IsAuthenticated
        {
            get
            {
                if (string.IsNullOrWhiteSpace(settings.GoogleClientId) || string.IsNullOrWhiteSpace(settings.GoogleClientSecret))
                {
                    return false;
                }

                if (credential != null)
                {
                    return true;
                }

                return CheckStoredCredentials();
            }
        }

        public async Task<UserCredential?> GetCredentialAsync(CancellationToken ct = default)
        {
            if (string.IsNullOrWhiteSpace(settings.GoogleClientId) || string.IsNullOrWhiteSpace(settings.GoogleClientSecret))
            {
                return null;
            }

            using var refreshCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            refreshCts.CancelAfter(TimeSpan.FromSeconds(15));
            var effectiveCt = refreshCts.Token;

            if (credential != null)
            {
                if (credential.Token.IsStale)
                {
                    try
                    {
                        await credential.RefreshTokenAsync(effectiveCt).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Failed refreshing Google Drive token. Re-authentication required.");
                        return null;
                    }
                }
                return credential;
            }

            var decryptedToken = tokenStorage.LoadDecryptedToken();
            if (!string.IsNullOrEmpty(decryptedToken))
            {
                try
                {
                    var token = JsonConvert.DeserializeObject<TokenResponse>(decryptedToken!);
                    if (token != null)
                    {
                        var flow = CreateFlow();
                        credential = new UserCredential(flow, "user", token);
                        if (credential.Token.IsStale)
                        {
                            var refreshed = await credential.RefreshTokenAsync(effectiveCt).ConfigureAwait(false);
                            if (refreshed)
                            {
                                tokenStorage.SaveEncryptedToken(JsonConvert.SerializeObject(credential.Token));
                            }
                        }
                        return credential;
                    }
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, "Failed to restore cached Google Drive token.");
                }
            }

            return null;
        }

        public async Task<UserCredential> AuthorizeInteractiveAsync(CancellationToken ct = default)
        {
            var flow = CreateFlow();
            var codeReceiver = new LocalServerCodeReceiver();

            credential = await new AuthorizationCodeInstalledApp(flow, codeReceiver).AuthorizeAsync("user", ct).ConfigureAwait(false);
            if (credential?.Token != null)
            {
                tokenStorage.SaveEncryptedToken(JsonConvert.SerializeObject(credential.Token));
            }

            return credential!;
        }

        public void Disconnect()
        {
            credential = null;
            tokenStorage.DeleteToken();
        }

        public async Task<DriveService> CreateDriveServiceAsync(CancellationToken ct = default)
        {
            var cred = await GetCredentialAsync(ct).ConfigureAwait(false);
            if (cred == null)
            {
                throw new InvalidOperationException("Google Drive user is not authenticated. Please log in through Settings.");
            }

            return new DriveService(new BaseClientService.Initializer
            {
                HttpClientInitializer = cred,
                ApplicationName = "PlayniteMobileDeltaSync"
            });
        }

        private GoogleAuthorizationCodeFlow CreateFlow()
        {
            var clientId = settings.GoogleClientId?.Trim();
            var clientSecret = settings.GoogleClientSecret?.Trim();

            if (string.IsNullOrWhiteSpace(clientId) || string.IsNullOrWhiteSpace(clientSecret))
            {
                throw new InvalidOperationException("Google OAuth Client ID and Client Secret are required. Please configure your Google Cloud credentials in Settings or choose Google Drive Desktop / Local Folder Sync.");
            }

            return new GoogleAuthorizationCodeFlow(new GoogleAuthorizationCodeFlow.Initializer
            {
                ClientSecrets = new ClientSecrets
                {
                    ClientId = clientId,
                    ClientSecret = clientSecret
                },
                // Strictly use least-privilege scope: drive.file only grants access to files created or opened by this app.
                // It CANNOT read, modify, or delete any other user files in Google Drive.
                Scopes = new[] { DriveService.Scope.DriveFile }
            });
        }
    }
}
