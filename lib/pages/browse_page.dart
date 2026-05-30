import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/tmdb_service.dart';
import '../widgets/movie_card.dart';
import '../widgets/buttons.dart';

class FilterOption {
  final String label;
  final String value;
  const FilterOption(this.label, this.value);
}

class BrowsePage extends StatefulWidget {
  final String title;
  final String mediaType; // 'movie' or 'tv'
  final List<FilterOption> genres;
  final List<FilterOption>? languages;
  final String defaultSort;

  const BrowsePage({
    super.key,
    required this.title,
    required this.mediaType,
    required this.genres,
    this.languages,
    this.defaultSort = 'popularity.desc',
  });

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final List<ContentModel> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  int _totalPages = 0;
  final ScrollController _scrollController = ScrollController();

  late String _selectedGenre;
  String _selectedLanguage = '';
  String _selectedYear = 'All';
  late String _selectedSort;

  final List<FilterOption> _years = [
    const FilterOption('All Years', 'All'),
    for (int y = DateTime.now().year; y >= 2010; y--) FilterOption('$y', '$y'),
    const FilterOption('Older', 'older'),
  ];

  late final List<FilterOption> _sorts;

  @override
  void initState() {
    super.initState();
    _selectedGenre = widget.genres.isNotEmpty ? widget.genres.first.value : '';
    _selectedSort = widget.defaultSort;

    _sorts = [
      const FilterOption('Popular', 'popularity.desc'),
      const FilterOption('Top Rated', 'vote_average.desc'),
      if (widget.mediaType == 'movie')
        const FilterOption('Latest', 'primary_release_date.desc')
      else
        const FilterOption('Latest', 'first_air_date.desc'),
    ];

    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 500 &&
          !_isLoading &&
          _hasMore) {
        _loadMore();
      }
    });
  }

  void _onFilterChanged() {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _totalPages = 0;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final params = <String, String>{
        'sort_by': _selectedSort,
      };

      if (_selectedGenre.isNotEmpty) {
        params['with_genres'] = _selectedGenre;
      }

      if (_selectedLanguage.isNotEmpty) {
        if (_selectedLanguage == 'other') {
          params['without_original_language'] = 'ja,zh';
        } else {
          params['with_original_language'] = _selectedLanguage;
        }
      }

      if (_selectedYear.isNotEmpty && _selectedYear != 'All') {
        if (_selectedYear == 'older') {
          if (widget.mediaType == 'movie') {
            params['primary_release_date.lte'] = '2009-12-31';
          } else {
            params['first_air_date.lte'] = '2009-12-31';
          }
        } else {
          if (widget.mediaType == 'movie') {
            params['primary_release_year'] = _selectedYear;
          } else {
            params['first_air_date_year'] = _selectedYear;
          }
        }
      }

      if (_selectedSort == 'vote_average.desc') {
        params['vote_count.gte'] = '50';
      }

      final result = await TmdbService.discoverBrowsePage(
        mediaType: widget.mediaType,
        page: _page,
        params: params,
      );

      if (mounted) {
        setState(() {
          _totalPages = result.totalPages;
          final newItems = result.items.map(ContentModel.fromTmdb).toList();
          if (newItems.isEmpty || _page >= _totalPages) {
            _hasMore = false;
          }
          _items.addAll(newItems);
          _page++;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildDropdown({
    required String value,
    required List<FilterOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(
            LucideIcons.chevronDown,
            color: Colors.white70,
            size: 16,
          ),
          focusColor: Colors.white24,
          dropdownColor: AppTheme.cardDark,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: options.map((opt) {
            return DropdownMenuItem(value: opt.value, child: Text(opt.label));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            pinned: true,
            elevation: 0,
            leading: HoverButton(
              onTap: () => Navigator.pop(context),
              backgroundColor: Colors.transparent,
              child: const Icon(LucideIcons.arrowLeft, color: Colors.white),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                height: 60,
                padding: const EdgeInsets.only(bottom: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      if (widget.genres.length > 1) ...[
                        _buildDropdown(
                          value: _selectedGenre,
                          options: widget.genres,
                          onChanged: (v) {
                            if (v != null) {
                              _selectedGenre = v;
                              _onFilterChanged();
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (widget.languages != null &&
                          widget.languages!.isNotEmpty) ...[
                        _buildDropdown(
                          value: _selectedLanguage,
                          options: widget.languages!,
                          onChanged: (v) {
                            if (v != null) {
                              _selectedLanguage = v;
                              _onFilterChanged();
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                      ],
                      _buildDropdown(
                        value: _selectedYear,
                        options: _years,
                        onChanged: (v) {
                          if (v != null) {
                            _selectedYear = v;
                            _onFilterChanged();
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildDropdown(
                        value: _selectedSort,
                        options: _sorts,
                        onChanged: (v) {
                          if (v != null) {
                            _selectedSort = v;
                            _onFilterChanged();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_items.isEmpty && _isLoading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          else if (_items.isEmpty && !_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No results found.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: layout.pagePadding,
                vertical: 16,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: layout.gridMaxExtent(
                    compact: 144,
                    tablet: 160,
                    desktop: 170,
                  ),
                  childAspectRatio: 0.52,
                  crossAxisSpacing: layout.isPhone ? 12 : 16,
                  mainAxisSpacing: layout.isPhone ? 16 : 24,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  if (index == _items.length) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    );
                  }
                  return MovieCard(
                    content: _items[index],
                    width: null,
                    margin: EdgeInsets.zero,
                  );
                }, childCount: _items.length + (_hasMore ? 1 : 0)),
              ),
            ),
        ],
      ),
    );
  }
}
