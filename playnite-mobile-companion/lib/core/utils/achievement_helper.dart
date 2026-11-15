/// Utility helper for inspecting and evaluating achievement payloads.
class AchievementHelper {
  AchievementHelper._();

  /// Determines whether an achievement is unlocked based on explicit flags or unlock timestamp.
  static bool isUnlocked(Map<String, dynamic> item) {
    final unlocked = item['unlocked'];
    final isUnlocked = item['is_unlocked'];

    if (unlocked == true ||
        isUnlocked == true ||
        unlocked == 1 ||
        isUnlocked == 1 ||
        unlocked == 'true' ||
        isUnlocked == 'true') {
      return true;
    }

    final dt = item['date_unlocked_utc'] ?? item['date_unlocked'] ?? item['unlock_time_utc'];
    return dt != null && dt.toString().trim().isNotEmpty;
  }
}
