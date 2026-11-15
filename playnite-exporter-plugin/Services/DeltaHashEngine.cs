using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Playnite.SDK.Models;
using PlayniteExporterPlugin.Addons;
using PlayniteExporterPlugin.Addons.Extractors;
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
                    if (existing.StateHash == null && candidate.StateHash != null)
                    {
                        existing.StateHash = candidate.StateHash;
                        diff.IndexHealed = true;
                    }
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

            var sb = new StringBuilder(512);
            sb.Append("Id:").Append(game.Id).Append(';');
            sb.Append("Name:").Append(game.Name).Append(';');
            sb.Append("SortingName:").Append(game.SortingName).Append(';');
            sb.Append("Playtime:").Append(game.Playtime).Append(';');
            sb.Append("PlayCount:").Append(game.PlayCount).Append(';');
            sb.Append("UserScore:").Append(game.UserScore).Append(';');
            sb.Append("CriticScore:").Append(game.CriticScore).Append(';');
            sb.Append("CommunityScore:").Append(game.CommunityScore).Append(';');
            sb.Append("Favorite:").Append(game.Favorite).Append(';');
            sb.Append("Hidden:").Append(game.Hidden).Append(';');
            sb.Append("IsInstalled:").Append(game.IsInstalled).Append(';');
            sb.Append("CompletionStatusId:").Append(game.CompletionStatusId).Append(';');
            sb.Append("InstallDirectory:").Append(game.InstallDirectory).Append(';');
            sb.Append("Notes:").Append(game.Notes).Append(';');
            sb.Append("Description:").Append(game.Description).Append(';');
            sb.Append("PlatformIds:").Append(game.PlatformIds != null ? string.Join(",", game.PlatformIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("GenreIds:").Append(game.GenreIds != null ? string.Join(",", game.GenreIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("CategoryIds:").Append(game.CategoryIds != null ? string.Join(",", game.CategoryIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("TagIds:").Append(game.TagIds != null ? string.Join(",", game.TagIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("DeveloperIds:").Append(game.DeveloperIds != null ? string.Join(",", game.DeveloperIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("PublisherIds:").Append(game.PublisherIds != null ? string.Join(",", game.PublisherIds.OrderBy(g => g)) : "").Append(';');
            sb.Append("Links:").Append(game.Links != null ? string.Join(",", game.Links.Where(l => l != null).OrderBy(l => l.Name).ThenBy(l => l.Url).Select(l => $"{l.Name}={l.Url}")) : "").Append(';');
            sb.Append("CoverImage:").Append(game.CoverImage).Append(';');
            sb.Append("BackgroundImage:").Append(game.BackgroundImage).Append(';');
            sb.Append("Icon:").Append(game.Icon).Append(';');

            if (addonRegistry != null)
            {
                var extensionsDataDir = Path.Combine(userDataDir, "ExtensionsData");
                var extraMetadataDir = Path.Combine(userDataDir, "ExtraMetadata");
                bool hasAddonDirs = Directory.Exists(extensionsDataDir) || Directory.Exists(extraMetadataDir);

                if (!hasAddonDirs)
                {
                    var extractors = addonRegistry.OrderedExtractors ??
                        addonRegistry.RegisteredExtractors.OrderBy(e => e.AddonKey, StringComparer.Ordinal).ToList();
                    for (int i = 0; i < extractors.Count; i++)
                    {
                        sb.Append("addon:").Append(extractors[i].AddonKey).Append("=;");
                    }
                }
                else
                {
                    var paExtractor = addonRegistry.PlayniteAchievementsExtractor ??
                        addonRegistry.RegisteredExtractors.FirstOrDefault(e => e.AddonKey == "playnite_achievements" || e is PlayniteAchievementsExtractor);

                    string? paHash = null;
                    if (paExtractor != null)
                    {
                        try
                        {
                            paHash = paExtractor.GetStateHash(game, userDataDir);
                        }
                        catch
                        {
                            paHash = null;
                        }
                    }

                    bool hasValidPaHash = !string.IsNullOrEmpty(paHash);
                    var extractors = addonRegistry.OrderedExtractors ??
                        addonRegistry.RegisteredExtractors.OrderBy(e => e.AddonKey, StringComparer.Ordinal).ToList();
                    var ssExtractor = addonRegistry.SuccessStoryExtractor;

                    for (int i = 0; i < extractors.Count; i++)
                    {
                        var extractor = extractors[i];
                        if (hasValidPaHash && (extractor == ssExtractor || extractor.AddonKey == "success_story" || extractor is SuccessStoryExtractor))
                        {
                            continue;
                        }

                        string? addonHash = null;
                        if (extractor == paExtractor)
                        {
                            addonHash = paHash;
                        }
                        else
                        {
                            try
                            {
                                addonHash = extractor.GetStateHash(game, userDataDir);
                            }
                            catch
                            {
                                // Ignore failure to ensure hash calculation does not throw
                            }
                        }
                        sb.Append("addon:").Append(extractor.AddonKey).Append('=').Append(addonHash).Append(';');
                    }
                }
            }

            return Sha256Hasher.ComputeStringHash(sb.ToString());
        }
    }
}
