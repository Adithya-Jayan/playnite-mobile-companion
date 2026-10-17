namespace PlayniteExporterPlugin.Models
{
    public class ExportProgressReport
    {
        public string Text { get; set; } = string.Empty;
        public double CurrentProgressValue { get; set; }
        public double ProgressMaxValue { get; set; }
        public bool IsIndeterminate { get; set; }

        public ExportProgressReport()
        {
        }

        public ExportProgressReport(string text, double current = 0, double max = 0, bool indeterminate = false)
        {
            Text = text;
            CurrentProgressValue = current;
            ProgressMaxValue = max;
            IsIndeterminate = indeterminate;
        }
    }
}
