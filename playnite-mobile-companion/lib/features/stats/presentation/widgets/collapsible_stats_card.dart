import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';

/// Reusable collapsible card for Stats Dashboard sections.
/// Allows headers to be tapped to expand or collapse section content.
class CollapsibleStatsCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String? badge;
  final Widget child;
  final bool? isExpanded;
  final bool isInitiallyExpanded;
  final ValueChanged<bool>? onToggle;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;

  const CollapsibleStatsCard({
    super.key,
    required this.title,
    required this.icon,
    this.iconColor = AppTheme.primaryLight,
    this.badge,
    required this.child,
    this.isExpanded,
    this.isInitiallyExpanded = true,
    this.onToggle,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.contentPadding = const EdgeInsets.only(left: 16, right: 16, bottom: 16),
  });

  @override
  State<CollapsibleStatsCard> createState() => _CollapsibleStatsCardState();
}

class _CollapsibleStatsCardState extends State<CollapsibleStatsCard> {
  late bool _selfExpanded;

  @override
  void initState() {
    super.initState();
    _selfExpanded = widget.isInitiallyExpanded;
  }

  bool get _isExpanded => widget.isExpanded ?? _selfExpanded;

  void _handleTap() {
    final next = !_isExpanded;
    if (widget.onToggle != null) {
      widget.onToggle!(next);
    }
    if (widget.isExpanded == null) {
      setState(() => _selfExpanded = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _isExpanded;

    return Card(
      margin: widget.margin,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _handleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.iconColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Text(
                        widget.badge!,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: expanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppTheme.textMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: expanded
                ? Padding(
                    padding: widget.contentPadding,
                    child: widget.child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
