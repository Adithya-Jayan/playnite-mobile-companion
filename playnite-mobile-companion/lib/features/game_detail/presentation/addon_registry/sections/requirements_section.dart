import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/features/sync/domain/sync_models.dart';
import '../i_addon_widget.dart';

class RequirementsSection implements IAddonSectionWidget {
  const RequirementsSection();

  @override
  String get addonKey => 'system_checker';

  @override
  int get displayOrder => 50;

  @override
  String get title => 'System Requirements';

  @override
  Widget buildSection(BuildContext context, Map<String, dynamic> addonData, UnifiedGamePayload game) {
    final minimum = addonData['minimum'] as Map<String, dynamic>? ?? {};
    final recommended = addonData['recommended'] as Map<String, dynamic>? ?? {};

    if (minimum.isEmpty && recommended.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.computer, color: AppTheme.accentCyan, size: 22),
                SizedBox(width: 8),
                Text(
                  'Hardware Requirements',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (minimum.isNotEmpty) ...[
              const Text('Minimum', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryLight)),
              const SizedBox(height: 6),
              _buildSpecsGrid(minimum),
            ],
            if (minimum.isNotEmpty && recommended.isNotEmpty) const SizedBox(height: 12),
            if (recommended.isNotEmpty) ...[
              const Text('Recommended', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentGreen)),
              const SizedBox(height: 6),
              _buildSpecsGrid(recommended),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpecsGrid(Map<String, dynamic> specs) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: specs.entries.map((entry) {
          final key = entry.key.replaceAll('_', ' ').toUpperCase();
          final val = entry.value.toString();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(key, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(val, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
