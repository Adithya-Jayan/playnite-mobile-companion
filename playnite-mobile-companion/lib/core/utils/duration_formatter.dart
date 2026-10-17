/// Utility class for formatting time durations (given strictly in seconds) into human-readable strings.
class DurationFormatter {
  /// Formats seconds into "Xh Ym", "Xh", or "Ym".
  /// Examples:
  ///   93612s -> "26h 0m"
  ///   3600s  -> "1h 0m"
  ///   125s   -> "2m"
  ///   0s     -> "0m"
  static String formatSecondsToHoursMinutes(int seconds) {
    if (seconds <= 0) return '0m';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }

  /// Formats seconds to single-decimal hours: e.g. 93612s -> "26.0h"
  static String formatSecondsToDecimalHours(int seconds) {
    if (seconds <= 0) return '0.0h';
    final hours = seconds / 3600.0;
    return '${hours.toStringAsFixed(1)}h';
  }

  /// Formats large total playtime into days and hours:
  /// e.g. 5125 hours -> "5,125 Hours (213 Days)"
  static String formatTotalPlaytimeSummary(int totalSeconds) {
    final totalHours = (totalSeconds / 3600.0).round();
    final days = (totalHours / 24.0).floor();
    final remainingHours = totalHours % 24;

    final formattedHours = _addCommas(totalHours);
    if (days > 0) {
      return '$formattedHours Hours ($days Days, $remainingHours Hours)';
    } else {
      return '$formattedHours Hours';
    }
  }

  static String _addCommas(int value) {
    final s = value.toString();
    final regExp = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(regExp, (Match m) => '${m[1]},');
  }

  /// Formats byte count to human-readable string: e.g. 2145728 -> "2.05 MB"
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}
