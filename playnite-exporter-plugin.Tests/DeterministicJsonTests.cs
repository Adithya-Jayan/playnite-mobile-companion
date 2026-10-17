using System;
using System.Collections.Generic;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Models;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class DeterministicJsonTests
    {
        [Fact]
        public void Serialize_PropertiesAlphabeticallySorted()
        {
            var payload = new UnifiedGamePayload
            {
                Id = Guid.Parse("11111111-2222-3333-4444-555555555555"),
                Name = "Alpha Test Game",
                PlaytimeSeconds = 3600,
                PlayCount = 5,
                IsInstalled = true
            };

            var json = DeterministicJsonSerializer.Serialize(payload);

            // "added_utc" should appear before "game_id", which should appear before "name"
            int indexAdded = json.IndexOf("\"added_utc\"");
            int indexGameId = json.IndexOf("\"game_id\"");
            int indexName = json.IndexOf("\"name\"");
            int indexPlaytime = json.IndexOf("\"playtime_seconds\"");

            Assert.True(indexAdded >= 0);
            Assert.True(indexGameId > indexAdded);
            Assert.True(indexName > indexGameId);
            Assert.True(indexPlaytime > indexName);
        }

        [Fact]
        public void Serialize_DictionaryKeysAlphabeticallySorted()
        {
            var dict1 = new Dictionary<string, object?>
            {
                ["zebra"] = 1,
                ["apple"] = 2,
                ["mango"] = 3
            };

            var dict2 = new Dictionary<string, object?>
            {
                ["apple"] = 2,
                ["mango"] = 3,
                ["zebra"] = 1
            };

            var json1 = DeterministicJsonSerializer.Serialize(dict1);
            var json2 = DeterministicJsonSerializer.Serialize(dict2);

            Assert.Equal(json1, json2);

            int indexApple = json1.IndexOf("\"apple\"");
            int indexMango = json1.IndexOf("\"mango\"");
            int indexZebra = json1.IndexOf("\"zebra\"");

            Assert.True(indexApple < indexMango);
            Assert.True(indexMango < indexZebra);
        }

        [Fact]
        public void Serialize_ProducesIdenticalSha256AcrossRuns()
        {
            var id = Guid.NewGuid();
            var p1 = new UnifiedGamePayload
            {
                Id = id,
                Name = "Consistent Game",
                PlaytimeSeconds = 7200,
                PlayCount = 10,
                AddedUtc = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc)
            };

            var p2 = new UnifiedGamePayload
            {
                Id = id,
                Name = "Consistent Game",
                PlaytimeSeconds = 7200,
                PlayCount = 10,
                AddedUtc = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc)
            };

            var json1 = DeterministicJsonSerializer.Serialize(p1);
            var json2 = DeterministicJsonSerializer.Serialize(p2);

            var hash1 = Sha256Hasher.ComputeStringHash(json1);
            var hash2 = Sha256Hasher.ComputeStringHash(json2);

            Assert.Equal(json1, json2);
            Assert.Equal(hash1, hash2);
            Assert.Equal(64, hash1.Length);
        }

        [Fact]
        public void Serialize_Iso8601UtcDateTimeFormatting()
        {
            var date = new DateTime(2026, 10, 15, 14, 30, 45, 123, DateTimeKind.Utc);
            var payload = new UnifiedGamePayload
            {
                Id = Guid.NewGuid(),
                AddedUtc = date
            };

            var json = DeterministicJsonSerializer.Serialize(payload);
            Assert.Contains("\"2026-10-15T14:30:45.123Z\"", json);
        }
    }
}
