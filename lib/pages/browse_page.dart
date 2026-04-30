import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/api_service.dart';
import '../widgets/movie_card.dart';

class FilterOption {
  final String label;
  final String value;
  const FilterOption(this.label, this.value);
}

class BrowsePage extends StatefulWidget {
  final String title;
  final int baseTypeId;
  final List<FilterOption> subTypes;
  final bool showArea;

  const BrowsePage({
    super.key,
    required this.title,
    required this.baseTypeId,
    required this.subTypes,
    this.showArea = true,
  });

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final List<ContentModel> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();

  late String _selectedType;
  String _selectedArea = 'All';
  String _selectedYear = 'All';
  String _selectedSort = 'time';

  final List<FilterOption> _areas = const [
    FilterOption('All Areas', 'All'),
    FilterOption('Mainland China', '大陆'),
    FilterOption('Hong Kong', '香港'),
    FilterOption('Taiwan', '台湾'),
    FilterOption('USA', '美国'),
    FilterOption('Korea', '韩国'),
    FilterOption('Japan', '日本'),
  ];

  final List<FilterOption> _years = [
    const FilterOption('All Years', 'All'),
    for (int y = DateTime.now().year; y >= 2010; y--) FilterOption('$y', '$y'),
    const FilterOption('Older', '2009'),
  ];

  final List<FilterOption> _sorts = const [
    FilterOption('Latest', 'time'),
    FilterOption('Popular', 'hits'),
    FilterOption('Top Rated', 'score'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.baseTypeId.toString();
    _loadMore();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500 &&
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
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final newItems = await ApiService().fetchFiltered(
        page: _page,
        typeId: int.tryParse(_selectedType),
        area: _selectedArea,
        year: _selectedYear,
        by: _selectedSort,
      );

      if (mounted) {
        setState(() {
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _items.addAll(newItems);
            _page++;
          }
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
          icon: const Icon(LucideIcons.chevronDown, color: Colors.white70, size: 16),
          dropdownColor: AppTheme.cardDark,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          items: options.map((opt) {
            return DropdownMenuItem(
              value: opt.value,
              child: Text(opt.label),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      if (widget.subTypes.isNotEmpty) ...[
                        _buildDropdown(
                          value: _selectedType,
                          options: widget.subTypes,
                          onChanged: (v) {
                            if (v != null) {
                              _selectedType = v;
                              _onFilterChanged();
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (widget.showArea) ...[
                        _buildDropdown(
                          value: _selectedArea,
                          options: _areas,
                          onChanged: (v) {
                            if (v != null) {
                              _selectedArea = v;
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
              child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
            )
          else if (_items.isEmpty && !_isLoading)
            const SliverFillRemaining(
              child: Center(
                child: Text('No results found.', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 24,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
                    }
                    return MovieCard(
                      content: _items[index],
                      width: null,
                      margin: EdgeInsets.zero,
                    );
                  },
                  childCount: _items.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
