import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';

/// Fallback addon section for gracefully inspecting unknown, future, or custom desktop extensions.
class FallbackAddonSection extends StatelessWidget {
  final String addonKey;
  final dynamic data;

  const FallbackAddonSection({
    super.key,
    required this.addonKey,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final title = _formatKeyToTitle(addonKey);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: const Icon(Icons.widgets_outlined, color: AppTheme.textMuted, size: 22),
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        subtitle: Text(
          'Extension Data ($addonKey)',
          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _prettyJson(data),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatKeyToTitle(String key) {
    return key
        .split('_')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  String _prettyJson(dynamic obj) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(obj);
    } catch (_) {
      return obj.toString();
    }
  }
}
