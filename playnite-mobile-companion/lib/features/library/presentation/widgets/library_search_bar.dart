import 'package:flutter/material.dart';
import '../../../../core/config/app_theme.dart';

class LibrarySearchBar extends StatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onQueryChanged;

  const LibrarySearchBar({
    super.key,
    required this.initialQuery,
    required this.onQueryChanged,
  });

  @override
  State<LibrarySearchBar> createState() => _LibrarySearchBarState();
}

class _LibrarySearchBarState extends State<LibrarySearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant LibrarySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery && _controller.text != widget.initialQuery) {
      _controller.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onQueryChanged,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search title, developers, genres...',
          prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textMuted),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: AppTheme.textMuted),
                  onPressed: () {
                    _controller.clear();
                    widget.onQueryChanged('');
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}
