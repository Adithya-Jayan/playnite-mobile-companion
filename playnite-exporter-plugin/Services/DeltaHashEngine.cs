using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Common;
using PlayniteExporterPlugin.Models;

namespace PlayniteExporterPlugin.Services
{
    public class DeltaHashEngine
    {
        public SyncDiff ComputeDiff(
            Dictionary<string, PlannedUpload> candidateFiles,
            SyncIndex previousIndex,
            bool detectDeletions = true)
        {
            if (candidateFiles == null) throw new ArgumentNullException(nameof(candidateFiles));
            if (previousIndex == null) previousIndex = new SyncIndex();

            var diff = new SyncDiff();

            // 1. Identify Added, Modified, and Unchanged candidate files
            foreach (var kvp in candidateFiles)
            {
                var path = kvp.Key;
                var candidate = kvp.Value;

                if (!previousIndex.Entries.TryGetValue(path, out var existing))
                {
                    diff.Added.Add(candidate);
                }
                else if (!string.Equals(candidate.Sha256, existing.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    candidate.ExistingDriveFileId = existing.DriveFileId;
                    diff.Modified.Add(candidate);
                }
                else
                {
                    // Candidate matches existing SHA-256 exactly
                    candidate.ExistingDriveFileId = existing.DriveFileId;
                    diff.Unchanged[path] = existing;
                }
            }

            // 2. Identify Deleted files (files present in previous index but no longer candidates)
            if (detectDeletions)
            {
                foreach (var kvp in previousIndex.Entries)
                {
                    var existingPath = kvp.Key;
                    var existingEntry = kvp.Value;

                    // Root control files and manifests are never deleted via library diffing
                    if (existingPath == "manifest.json" ||
                        existingPath == "sync_index.json" ||
                        existingEntry.Category == "manifest")
                    {
                        continue;
                    }

                    if (!candidateFiles.ContainsKey(existingPath))
                    {
                        diff.Deleted.Add(new PlannedDeletion(
                            existingPath,
                            existingEntry.DriveFileId,
                            existingEntry.Category
                        ));
                    }
                }
            }

            return diff;
        }

        public string ComputeGameStateHash(Game game, string userDataDir, AddonExtractorRegistry? addonRegistry)
        {
            if (game == null) throw new ArgumentNullException(nameof(game));

            var sb = new StringBuilder();
            sb.Append($"Id:{game.Id};");
            sb.Append($"Name:{game.Name};");
            sb.Append($"SortingName:{game.SortingName};");
            sb.Append($"Playtime:{game.Playtime};");
            sb.Append($"PlayCount:{game.PlayCount};");
            sb.Append($"UserScore:{game.UserScore};");
            sb.Append($"CriticScore:{game.CriticScore};");
            sb.Append($"CommunityScore:{game.CommunityScore};");
            sb.Append($"Favorite:{game.Favorite};");
            sb.Append($"Hidden:{game.Hidden};");
            sb.Append($"IsInstalled:{game.IsInstalled};");
            sb.Append($"CompletionStatusId:{game.CompletionStatusId};");
            sb.Append($"InstallDirectory:{game.InstallDirectory};");
            sb.Append($"Notes:{game.Notes};");
            sb.Append($"Description:{game.Description};");
            sb.Append($"PlatformIds:{(game.PlatformIds != null ? string.Join(",", game.PlatformIds.OrderBy(g => g)) : "")};");
            sb.Append($"GenreIds:{(game.GenreIds != null ? string.Join(",", game.GenreIds.OrderBy(g => g)) : "")};");
            sb.Append($"CategoryIds:{(game.CategoryIds != null ? string.Join(",", game.CategoryIds.OrderBy(g => g)) : "")};");
            sb.Append($"TagIds:{(game.TagIds != null ? string.Join(",", game.TagIds.OrderBy(g => g)) : "")};");
            sb.Append($"DeveloperIds:{(game.DeveloperIds != null ? string.Join(",", game.DeveloperIds.OrderBy(g => g)) : "")};");
            sb.Append($"PublisherIds:{(game.PublisherIds != null ? string.Join(",", game.PublisherIds.OrderBy(g => g)) : "")};");
            sb.Append($"Links:{(game.Links != null ? string.Join(",", game.Links.Where(l => l != null).OrderBy(l => l.Name).ThenBy(l => l.Url).Select(l => $"{l.Name}={l.Url}")) : "")};");
            sb.Append($"CoverImage:{game.CoverImage};");
            sb.Append($"BackgroundImage:{game.BackgroundImage};");
            sb.Append($"Icon:{game.Icon};");

            if (addonRegistry != null)
            {
                foreach (var extractor in addonRegistry.RegisteredExtractors.OrderBy(e => e.AddonKey, StringComparer.Ordinal))
                {
                    string? addonHash = null;
                    try
                    {
                        addonHash = extractor.GetStateHash(game, userDataDir);
                    }
                    catch
                    {
                        // Ignore failure to ensure hash calculation does not throw
                    }
                    sb.Append($"addon:{extractor.AddonKey}={addonHash};");
                }
            }

            return Sha256Hasher.ComputeStringHash(sb.ToString());
        }
    }
}
