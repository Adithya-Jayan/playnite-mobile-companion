import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';

class FilterDrawer extends StatefulWidget {
  final GameFilterCriteria currentCriteria;
  final FilterTaxonomies taxonomies;
  final ValueChanged<GameFilterCriteria> onApply;
  final VoidCallback onReset;

  const FilterDrawer({
    super.key,
    required this.currentCriteria,
    required this.taxonomies,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<FilterDrawer> createState() => _FilterDrawerState();
}

class _FilterDrawerState extends State<FilterDrawer> {
  late Set<String> _platforms;
  late Set<String> _sources;
  late Set<String> _genres;
  late Set<String> _completionStatuses;
  late bool? _isInstalled;
  late bool? _isFavorite;
  double _minScore = 0;

  @override
  void initState() {
    super.initState();
    _platforms = Set.from(widget.currentCriteria.platforms);
    _sources = Set.from(widget.currentCriteria.sources);
    _genres = Set.from(widget.currentCriteria.genres);
    _completionStatuses = Set.from(widget.currentCriteria.completionStatuses);
    _isInstalled = widget.currentCriteria.isInstalled;
    _isFavorite = widget.currentCriteria.isFavorite;
    _minScore = (widget.currentCriteria.minScore ?? 0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: AppTheme.primaryLight),
                  const SizedBox(width: 8),
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      widget.onReset();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Reset', style: TextStyle(color: AppTheme.textMuted)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Scrollable Filter Sections
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Toggles
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Installed Only', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                    activeThumbColor: AppTheme.accentGreen,
                    value: _isInstalled == true,
                    onChanged: (val) {
                      setState(() => _isInstalled = val ? true : null);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Favorites Only', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                    activeThumbColor: Colors.pinkAccent,
                    value: _isFavorite == true,
                    onChanged: (val) {
                      setState(() => _isFavorite = val ? true : null);
                    },
                  ),
                  const Divider(),

                  // Sources
                  if (widget.taxonomies.sources.isNotEmpty) ...[
                    _buildSectionHeader('Sources & Storefronts', _sources.length),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.taxonomies.sources.map((s) {
                        final isSelected = _sources.contains(s);
                        return FilterChip(
                          label: Text(s),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              val ? _sources.add(s) : _sources.remove(s);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Completion Statuses
                  if (widget.taxonomies.completionStatuses.isNotEmpty) ...[
                    _buildSectionHeader('Completion Status', _completionStatuses.length),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.taxonomies.completionStatuses.map((cs) {
                        final isSelected = _completionStatuses.contains(cs);
                        return FilterChip(
                          label: Text(cs),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              val ? _completionStatuses.add(cs) : _completionStatuses.remove(cs);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Platforms
                  if (widget.taxonomies.platforms.isNotEmpty) ...[
                    _buildSectionHeader('Platforms', _platforms.length),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.taxonomies.platforms.map((p) {
                        final isSelected = _platforms.contains(p);
                        return FilterChip(
                          label: Text(p),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              val ? _platforms.add(p) : _platforms.remove(p);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Genres
                  if (widget.taxonomies.genres.isNotEmpty) ...[
                    _buildSectionHeader('Genres', _genres.length),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.taxonomies.genres.map((g) {
                        final isSelected = _genres.contains(g);
                        return FilterChip(
                          label: Text(g),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              val ? _genres.add(g) : _genres.remove(g);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Minimum Score Slider
                  _buildSectionHeader('Minimum Score: ${_minScore.toInt()}%', 0),
                  Slider(
                    value: _minScore,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: AppTheme.primary,
                    label: '${_minScore.toInt()}%',
                    onChanged: (val) => setState(() => _minScore = val),
                  ),
                ],
              ),
            ),

            // Apply Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final criteria = widget.currentCriteria.copyWith(
                      platforms: _platforms,
                      sources: _sources,
                      genres: _genres,
                      completionStatuses: _completionStatuses,
                      isInstalled: _isInstalled,
                      isFavorite: _isFavorite,
                      minScore: _minScore > 0 ? _minScore.toInt() : null,
                      clearInstalled: _isInstalled == null,
                      clearFavorite: _isFavorite == null,
                      clearScores: _minScore == 0,
                    );
                    widget.onApply(criteria);
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Apply Filters',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
