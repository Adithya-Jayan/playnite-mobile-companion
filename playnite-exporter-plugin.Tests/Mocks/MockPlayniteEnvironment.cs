using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Linq.Expressions;
using Moq;
using Playnite.SDK;
using Playnite.SDK.Models;

namespace PlayniteExporterPlugin.Tests.Mocks
{
    public class MockPlayniteEnvironment
    {
        public Mock<IPlayniteAPI> MockApi { get; } = new();
        public Mock<IGameDatabaseAPI> MockDb { get; } = new();
        public Mock<IPlaynitePathsAPI> MockPaths { get; } = new();
        public List<Game> Games { get; } = new();
        public Dictionary<string, string> FileMap { get; } = new();

        public MockPlayniteEnvironment(string configurationPath)
        {
            MockPaths.Setup(p => p.ConfigurationPath).Returns(configurationPath);
            MockPaths.Setup(p => p.ExtensionsDataPath).Returns(Path.Combine(configurationPath, "ExtensionsData"));
            MockApi.Setup(a => a.Paths).Returns(MockPaths.Object);

            // Games collection
            var mockGames = new Mock<IItemCollection<Game>>();
            mockGames.Setup(c => c.Count).Returns(() => Games.Count);
            mockGames.Setup(c => c.GetEnumerator()).Returns(() => Games.GetEnumerator());
            mockGames.Setup(c => c.CopyTo(It.IsAny<Game[]>(), It.IsAny<int>()))
                .Callback<Game[], int>((arr, idx) => Games.CopyTo(arr, idx));
            mockGames.Setup(c => c.Get(It.IsAny<Guid>())).Returns((Guid id) => Games.FirstOrDefault(g => g.Id == id));
            MockDb.Setup(d => d.Games).Returns(mockGames.Object);

            // Taxonomies
            SetupCollection<GameSource>(MockDb, d => d.Sources, new List<GameSource>());
            SetupCollection<Platform>(MockDb, d => d.Platforms, new List<Platform>());
            SetupCollection<Genre>(MockDb, d => d.Genres, new List<Genre>());
            SetupCollection<Company>(MockDb, d => d.Companies, new List<Company>());
            SetupCollection<Tag>(MockDb, d => d.Tags, new List<Tag>());
            SetupCollection<Category>(MockDb, d => d.Categories, new List<Category>());
            SetupCollection<Series>(MockDb, d => d.Series, new List<Series>());
            SetupCollection<AgeRating>(MockDb, d => d.AgeRatings, new List<AgeRating>());
            SetupCollection<Region>(MockDb, d => d.Regions, new List<Region>());
            SetupCollection<GameFeature>(MockDb, d => d.Features, new List<GameFeature>());
            SetupCollection<CompletionStatus>(MockDb, d => d.CompletionStatuses, new List<CompletionStatus>());

            MockDb.Setup(d => d.GetFullFilePath(It.IsAny<string>()))
                  .Returns((string key) => FileMap.TryGetValue(key, out var path) ? path : key);

            MockApi.Setup(a => a.Database).Returns(MockDb.Object);
        }

        private static void SetupCollection<T>(Mock<IGameDatabaseAPI> db, Expression<Func<IGameDatabaseAPI, IItemCollection<T>>> property, List<T> list) where T : DatabaseObject
        {
            var mockCol = new Mock<IItemCollection<T>>();
            mockCol.Setup(c => c.Count).Returns(() => list.Count);
            mockCol.Setup(c => c.GetEnumerator()).Returns(() => list.GetEnumerator());
            mockCol.Setup(c => c.CopyTo(It.IsAny<T[]>(), It.IsAny<int>()))
                .Callback<T[], int>((arr, idx) => list.CopyTo(arr, idx));
            mockCol.Setup(c => c.Get(It.IsAny<Guid>())).Returns((Guid id) => list.FirstOrDefault(i => i.Id == id));
            mockCol.Setup(c => c.Add(It.IsAny<T>())).Callback<T>(item => list.Add(item));
            mockCol.Setup(c => c.Remove(It.IsAny<T>())).Returns<T>(item => list.Remove(item));
            db.Setup(property).Returns(mockCol.Object);
        }
    }
}
