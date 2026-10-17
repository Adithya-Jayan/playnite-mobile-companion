using System;
using System.Globalization;
using System.Windows.Data;

namespace PlayniteExporterPlugin.Configuration
{
    public class EnumBooleanConverter : IValueConverter
    {
        public static readonly EnumBooleanConverter Instance = new();

        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value == null || parameter == null) return false;
            var checkValue = value.ToString();
            var targetValue = parameter.ToString();
            return string.Equals(checkValue, targetValue, StringComparison.OrdinalIgnoreCase);
        }

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is bool isChecked && isChecked && parameter != null)
            {
                return Enum.Parse(targetType, parameter.ToString());
            }
            return Binding.DoNothing;
        }
    }
}
