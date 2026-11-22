using System;
using System.Data.SQLite;
using System.IO;

namespace PlayniteExporterPlugin.Tests.Helpers
{
    /// <summary>
    /// Shared test fixture helper providing canonical SQLite database initialization
    /// and seeding for PlayniteAchievements extension mocks.
    /// </summary>
    public static class AchievementDbTestHelper
    {
        public static void InitializeSchema(SQLiteConnection connection)
        {
            if (connection == null) throw new ArgumentNullException(nameof(connection));

            using var cmd = connection.CreateCommand();
            cmd.CommandText = @"
                CREATE TABLE IF NOT EXISTS Users (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ProviderKey TEXT NULL COLLATE NOCASE,
                    ExternalUserId TEXT NULL COLLATE NOCASE,
                    DisplayName TEXT NULL,
                    IsCurrentUser INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS Games (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ProviderKey TEXT NULL COLLATE NOCASE,
                    PlayniteGameId TEXT NULL,
                    GameName TEXT NULL
                );

                CREATE TABLE IF NOT EXISTS UserGameProgress (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    UserId INTEGER NOT NULL,
                    GameId INTEGER NOT NULL,
                    CacheKey TEXT NULL COLLATE NOCASE,
                    HasAchievements INTEGER NOT NULL DEFAULT 0,
                    AchievementsUnlocked INTEGER NOT NULL DEFAULT 0,
                    TotalAchievements INTEGER NOT NULL DEFAULT 0,
                    LastUpdatedUtc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS AchievementDefinitions (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    GameId INTEGER NOT NULL,
                    ApiName TEXT NOT NULL COLLATE NOCASE,
                    DisplayName TEXT NULL,
                    Description TEXT NULL,
                    UnlockedIconPath TEXT NULL,
                    LockedIconPath TEXT NULL,
                    Points REAL NULL,
                    Category TEXT NOT NULL DEFAULT 'Default',
                    Hidden INTEGER NOT NULL DEFAULT 0,
                    GlobalPercentUnlocked REAL NULL,
                    ProgressMax REAL NULL
                );

                CREATE TABLE IF NOT EXISTS UserAchievements (
                    Id INTEGER PRIMARY KEY AUTOINCREMENT,
                    UserGameProgressId INTEGER NOT NULL,
                    AchievementDefinitionId INTEGER NOT NULL,
                    Unlocked INTEGER NOT NULL DEFAULT 0,
                    UnlockTimeUtc TEXT NULL,
                    ProgressNum REAL NULL,
                    ProgressDenom REAL NULL
                );";
            cmd.ExecuteNonQuery();
        }

        public static void CreateAndInitializeDatabase(string dbPath)
        {
            if (string.IsNullOrEmpty(dbPath)) throw new ArgumentNullException(nameof(dbPath));

            var dir = Path.GetDirectoryName(dbPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            if (File.Exists(dbPath))
            {
                File.Delete(dbPath);
            }

            SQLiteConnection.CreateFile(dbPath);

            var cs = new SQLiteConnectionStringBuilder
            {
                DataSource = dbPath,
                ReadOnly = false
            }.ToString();

            using var conn = new SQLiteConnection(cs);
            conn.Open();
            InitializeSchema(conn);
        }
    }
}
