import 'package:flutter/material.dart';
import 'package:playnite_mobile_companion/core/config/app_theme.dart';
import 'package:playnite_mobile_companion/core/database/daos/taxonomy_dao.dart';
import 'package:playnite_mobile_companion/features/library/domain/game_filter_criteria.dart';
import 'package:playnite_mobile_companion/features/settings/data/gallery_settings_repository.dart';

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
  double _maxHltbHours = 0; // 0 = Any / Unlimited

  // Utility filter mode (single select)
  late UtilityFilterMode _utilityMode;

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
    _maxHltbHours = (widget.currentCriteria.hltbMaxHours ?? 0).toDouble();

    _utilityMode = widget.currentCriteria.utilityMode;
  }

  String _getScoreLabel() {
    switch (widget.currentCriteria.ratingScoreSource) {
      case RatingScoreSource.community:
        return 'Community Score';
      case RatingScoreSource.composite:
        return 'Composite Score';
      case RatingScoreSource.critic:
        return 'Critic Score';
      case RatingScoreSource.user:
        return 'User Score';
    }
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

                  // Collapsible Sources & Storefronts
                  if (widget.taxonomies.sources.isNotEmpty)
                    _buildCollapsibleSection(
                      title: 'Sources & Storefronts',
                      items: widget.taxonomies.sources,
                      selectedItems: _sources,
                      onToggle: (item) {
                        setState(() {
                          _sources.contains(item) ? _sources.remove(item) : _sources.add(item);
                        });
                      },
                    ),

                  // Collapsible Completion Status
                  if (widget.taxonomies.completionStatuses.isNotEmpty)
                    _buildCollapsibleSection(
                      title: 'Completion Status',
                      items: widget.taxonomies.completionStatuses,
                      selectedItems: _completionStatuses,
                      onToggle: (item) {
                        setState(() {
                          _completionStatuses.contains(item)
                              ? _completionStatuses.remove(item)
                              : _completionStatuses.add(item);
                        });
                      },
                    ),

                  // Collapsible Platforms
                  if (widget.taxonomies.platforms.isNotEmpty)
                    _buildCollapsibleSection(
                      title: 'Platforms',
                      items: widget.taxonomies.platforms,
                      selectedItems: _platforms,
                      onToggle: (item) {
                        setState(() {
                          _platforms.contains(item) ? _platforms.remove(item) : _platforms.add(item);
                        });
                      },
                    ),

                  // Collapsible Genres
                  if (widget.taxonomies.genres.isNotEmpty)
                    _buildCollapsibleSection(
                      title: 'Genres',
                      items: widget.taxonomies.genres,
                      selectedItems: _genres,
                      onToggle: (item) {
                        setState(() {
                          _genres.contains(item) ? _genres.remove(item) : _genres.add(item);
                        });
                      },
                    ),

                  const SizedBox(height: 8),
                  const Divider(),

                  // Rating Score Slider (defaults to Community Score)
                  _buildScoreHeader(),
                  Slider(
                    value: _minScore,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: AppTheme.primary,
                    label: '${_minScore.toInt()}%',
                    onChanged: (val) => setState(() => _minScore = val),
                  ),

                  // HowLongToBeat Duration Filter Slider
                  _buildHltbHeader(),
                  Slider(
                    value: _maxHltbHours,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: AppTheme.accentCyan,
                    label: _maxHltbHours > 0 ? '${_maxHltbHours.toInt()}h' : 'Any',
                    onChanged: (val) => setState(() => _maxHltbHours = val),
                  ),

                  const SizedBox(height: 8),
                  const Divider(),

                  // Dedicated Utility & Diagnostic Filters Section
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: _utilityMode != UtilityFilterMode.none,
                      tilePadding: EdgeInsets.zero,
                      leading: const Icon(Icons.build_circle_outlined, color: AppTheme.primaryLight, size: 20),
                      title: const Text(
                        'Utility & Diagnostics',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('None'),
                                  selected: _utilityMode == UtilityFilterMode.none,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (_) => setState(() => _utilityMode = UtilityFilterMode.none),
                                ),
                                ChoiceChip(
                                  label: const Text('Only Hidden'),
                                  selected: _utilityMode == UtilityFilterMode.onlyHidden,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (sel) => setState(() => _utilityMode = sel ? UtilityFilterMode.onlyHidden : UtilityFilterMode.none),
                                ),
                                ChoiceChip(
                                  label: const Text('Only Duplicates'),
                                  selected: _utilityMode == UtilityFilterMode.onlyDuplicates,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (sel) => setState(() => _utilityMode = sel ? UtilityFilterMode.onlyDuplicates : UtilityFilterMode.none),
                                ),
                                ChoiceChip(
                                  label: const Text('Only Unplayed'),
                                  selected: _utilityMode == UtilityFilterMode.onlyUnplayed,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (sel) => setState(() => _utilityMode = sel ? UtilityFilterMode.onlyUnplayed : UtilityFilterMode.none),
                                ),
                                ChoiceChip(
                                  label: const Text('Missing Covers'),
                                  selected: _utilityMode == UtilityFilterMode.missingCovers,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (sel) => setState(() => _utilityMode = sel ? UtilityFilterMode.missingCovers : UtilityFilterMode.none),
                                ),
                                ChoiceChip(
                                  label: const Text('Missing Microtrailers'),
                                  selected: _utilityMode == UtilityFilterMode.missingMicrotrailers,
                                  selectedColor: AppTheme.primary,
                                  onSelected: (sel) => setState(() => _utilityMode = sel ? UtilityFilterMode.missingMicrotrailers : UtilityFilterMode.none),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
                      hltbMaxHours: _maxHltbHours > 0 ? _maxHltbHours.toInt() : null,
                      utilityMode: _utilityMode,
                      clearInstalled: _isInstalled == null,
                      clearFavorite: _isFavorite == null,
                      clearScores: _minScore == 0,
                      clearHltb: _maxHltbHours == 0,
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

  Widget _buildCollapsibleSection({
    required String title,
    required List<String> items,
    required Set<String> selectedItems,
    required ValueChanged<String> onToggle,
  }) {
    final count = selectedItems.length;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: count > 0,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.map((item) {
                final isSelected = selectedItems.contains(item);
                return FilterChip(
                  label: Text(item),
                  selected: isSelected,
                  selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  onSelected: (_) => onToggle(item),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Minimum ${_getScoreLabel()}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          Text(
            _minScore > 0 ? '${_minScore.toInt()}%' : 'Any',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _minScore > 0 ? AppTheme.primaryLight : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHltbHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Max Beat Time (HLTB)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          Text(
            _maxHltbHours > 0 ? 'Under ${_maxHltbHours.toInt()}h' : 'Any',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _maxHltbHours > 0 ? AppTheme.accentCyan : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
