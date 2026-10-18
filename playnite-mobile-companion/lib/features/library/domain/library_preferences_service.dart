import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_filter_criteria.dart';
import 'sort_options.dart';

/// Service for persisting and restoring active library sort, view mode, and filter state.
class LibraryPreferencesService {
  static const String _sortFieldKey = 'pref_sort_field';
  static const String _sortDirectionKey = 'pref_sort_direction';
  static const String _viewModeKey = 'pref_view_mode';
  static const String _filterCriteriaKey = 'pref_filter_criteria_json';

  Future<void> saveSortOption(SortOption option) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortFieldKey, option.field.name);
      await prefs.setString(_sortDirectionKey, option.direction.name);
    } catch (_) {}
  }

  Future<SortOption> loadSortOption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fieldName = prefs.getString(_sortFieldKey);
      final directionName = prefs.getString(_sortDirectionKey);

      if (fieldName == null) return SortOption.titleAsc;

      final field = SortField.values.firstWhere(
        (f) => f.name == fieldName,
        orElse: () => SortField.title,
      );
      final direction = SortDirection.values.firstWhere(
        (d) => d.name == directionName,
        orElse: () => SortDirection.ascending,
      );

      return SortOption(field: field, direction: direction);
    } catch (_) {
      return SortOption.titleAsc;
    }
  }

  Future<void> saveViewMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModeKey, mode);
    } catch (_) {}
  }

  Future<String?> loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_viewModeKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFilterCriteria(GameFilterCriteria criteria) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_filterCriteriaKey, jsonEncode(criteria.toJson()));
    } catch (_) {}
  }

  Future<GameFilterCriteria?> loadFilterCriteria() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_filterCriteriaKey);
      if (raw == null || raw.isEmpty) return null;
      return GameFilterCriteria.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
