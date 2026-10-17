using System;
using System.Collections.Generic;
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
    }
}
