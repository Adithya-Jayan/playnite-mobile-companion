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
            else
            {
                double currentRate;
                lock (lockObj)
                {
                    double overallRate = completed / elapsed.TotalSeconds;

                    // Calculate recent rate over last interval if applicable
                    var nowTicks = stopwatch.ElapsedMilliseconds;
                    var intervalMs = nowTicks - lastReportTicks;
                    if (intervalMs >= 1000 && completed > lastCompleted)
                    {
                        double recentRate = (double)(completed - lastCompleted) / (intervalMs / 1000.0);
                        smoothedRate = (smoothedRate <= 0) ? recentRate : (smoothedRate * 0.7) + (recentRate * 0.3);
                        lastReportTicks = nowTicks;
                        lastCompleted = completed;
                    }

                    currentRate = smoothedRate > 0 ? (smoothedRate * 0.6 + overallRate * 0.4) : overallRate;
                }

                if (currentRate > 0.01 && remainingItems > 0)
                {
                    double remainingSeconds = remainingItems / currentRate;
                    var etaSpan = TimeSpan.FromSeconds(remainingSeconds);
                    etaText = $"ETA: {FormatTimeSpan(etaSpan)}";
                }
                else if (remainingItems == 0)
                {
                    etaText = "Finishing...";
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
                var mins = (int)ts.TotalMinutes;
                var secs = ts.Seconds;
                return secs > 0 ? $"{mins}m {secs}s" : $"{mins}m";
            }
            var hours = (int)ts.TotalHours;
            var remainMins = ts.Minutes;
            return remainMins > 0 ? $"{hours}h {remainMins}m" : $"{hours}h";
        }
    }
}
