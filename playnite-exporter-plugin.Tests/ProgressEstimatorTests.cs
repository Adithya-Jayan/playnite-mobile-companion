using System;
using System.Threading;
using PlayniteExporterPlugin.Common;
using Xunit;

namespace PlayniteExporterPlugin.Tests
{
    public class ProgressEstimatorTests
    {
        [Fact]
        public void Format_StepZero_ReturnsEstimatingETA()
        {
            var estimator = new ProgressEstimator(100);
            var result = estimator.Format(0, "Starting upload");

            Assert.Contains("Estimating ETA...", result);
            Assert.Contains("0%", result);
            Assert.Contains("Starting upload", result);
        }

        [Fact]
        public void Format_WithProgress_CalculatesPercentAndDescription()
        {
            var estimator = new ProgressEstimator(100);
            var result = estimator.Format(50, "Uploading item 50");

            Assert.Contains("50%", result);
            Assert.Contains("Uploading item 50", result);
        }

        [Fact]
        public void Format_AllItemsCompleted_ReturnsFinishingOrComplete()
        {
            var estimator = new ProgressEstimator(10);
            var result = estimator.Format(10, "Finished all uploads");

            Assert.Contains("100%", result);
            Assert.Contains("Finished all uploads", result);
        }
    }
}
