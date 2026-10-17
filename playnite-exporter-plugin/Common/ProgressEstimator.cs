using System;
using System.Diagnostics;
using System.Threading;

namespace PlayniteExporterPlugin.Common
{
    /// <summary>
    /// Thread-safe progress and ETA estimator for multi-threaded upload/export operations.
    /// Provides two-line formatted ETA and progress strings:
    /// Line 1: ETA and percentage / count statistics
    /// Line 2: Current item and action details
    /// </summary>
    public class ProgressEstimator
    {
        private readonly Stopwatch stopwatch = new();
        private readonly int totalItems;
        private readonly object lockObj = new();
        private double smoothedEtaSeconds = -1;
        private double smoothedRate = 0;
        private long lastReportTicks = 0;
        private int lastCompleted = 0;

        public ProgressEstimator(int totalItems)
        {
            this.totalItems = Math.Max(1, totalItems);
            stopwatch.Start();
        }

        public string Format(int completed, string description)
        {
            var elapsed = stopwatch.Elapsed;
            double percent = Math.Min(100.0, Math.Max(0.0, (double)completed / totalItems * 100.0));
            int remainingItems = Math.Max(0, totalItems - completed);

            string etaText;
            if (completed < 3 || elapsed.TotalSeconds < 1.5)
            {
                etaText = "Estimating ETA...";
            }
            else if (remainingItems == 0)
            {
                etaText = "Finishing...";
            }
            else
            {
                lock (lockObj)
                {
                    double overallRate = completed / elapsed.TotalSeconds;

                    // Rolling rate window over at least 2.5 seconds to bridge multi-threaded burst intervals
                    var nowTicks = stopwatch.ElapsedMilliseconds;
                    var intervalMs = nowTicks - lastReportTicks;
                    if (intervalMs >= 2500 && completed > lastCompleted)
                    {
                        double windowRate = (double)(completed - lastCompleted) / (intervalMs / 1000.0);
                        smoothedRate = (smoothedRate <= 0) ? windowRate : (smoothedRate * 0.7) + (windowRate * 0.3);
                        lastReportTicks = nowTicks;
                        lastCompleted = completed;
                    }

                    // Balance between cumulative average rate (which settles) and recent window rate
                    // As more items finish, cumulative rate carries more weight
                    double progressWeight = Math.Min(0.85, (double)completed / totalItems);
                    double effectiveRate = (smoothedRate > 0)
                        ? (overallRate * (0.5 + progressWeight * 0.4)) + (smoothedRate * (0.5 - progressWeight * 0.4))
                        : overallRate;

                    if (effectiveRate > 0.01)
                    {
                        double rawEta = remainingItems / effectiveRate;

                        // Low-pass exponential moving average filter directly on the ETA seconds:
                        // Damps out burst spikes from parallel network I/O and creates a calm countdown
                        if (smoothedEtaSeconds < 0)
                        {
                            smoothedEtaSeconds = rawEta;
                        }
                        else
                        {
                            smoothedEtaSeconds = (smoothedEtaSeconds * 0.85) + (rawEta * 0.15);
                        }
                    }
                }

                if (smoothedEtaSeconds > 0)
                {
                    var etaSpan = TimeSpan.FromSeconds(smoothedEtaSeconds);
                    etaText = $"ETA: {FormatTimeSpan(etaSpan)}";
                }
                else
                {
                    etaText = "Estimating...";
                }
            }

            // Two-line layout:
            // Line 1: ETA & progress percentage
            // Line 2: Current item description
            return $"{etaText} • {percent:F0}% ({completed}/{totalItems})\r\n{description}";
        }

        private static string FormatTimeSpan(TimeSpan ts)
        {
            if (ts.TotalSeconds < 60)
            {
                return $"{Math.Max(1, (int)Math.Round(ts.TotalSeconds))}s";
            }
            if (ts.TotalHours < 1)
            {
                var totalSecs = (int)Math.Round(ts.TotalSeconds);
                // Quantize to 5-second intervals when between 1m and 10m to prevent visual thrashing
                if (totalSecs < 600)
                {
                    totalSecs = (int)(Math.Round(totalSecs / 5.0) * 5);
                }
                var mins = totalSecs / 60;
                var secs = totalSecs % 60;
                return secs > 0 ? $"{mins}m {secs}s" : $"{mins}m";
            }
            var hours = (int)ts.TotalHours;
            var remainMins = ts.Minutes;
            return remainMins > 0 ? $"{hours}h {remainMins}m" : $"{hours}h";
        }
    }
}
