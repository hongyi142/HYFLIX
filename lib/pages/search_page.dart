import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/api_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/movie_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final ApiService _api = ApiService();
  List<ContentModel> _results = [];
  bool _isSearching = false;
  String? _translatedQuery;
  List<String> _searchHistory = [];
  static const int _maxHistory = 20;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    if (mounted) setState(() => _searchHistory = history);
  }

  Future<void> _saveToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchHistory.remove(trimmed);
    _searchHistory.insert(0, trimmed);
    if (_searchHistory.length > _maxHistory) {
      _searchHistory = _searchHistory.sublist(0, _maxHistory);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _searchHistory);
  }

  Future<void> _removeFromHistory(String query) async {
    _searchHistory.remove(query);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _searchHistory);
    if (mounted) setState(() {});
  }

  Future<void> _clearHistory() async {
    _searchHistory.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    if (mounted) setState(() {});
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    _saveToHistory(query);

    setState(() {
      _isSearching = true;
      _results = [];
      _translatedQuery = null;
    });

    try {
      // Query TMDB first for all queries to ensure unique records and rich metadata
      final tmdbResults = await TmdbService.searchMultiple(query, maxResults: 20);
      List<ContentModel> results = tmdbResults.map((tmdb) => ContentModel.fromTmdb(tmdb)).toList();

      // Fallback: search VOD providers if TMDB returned no results
      if (results.isEmpty) {
        results = await _searchVod([query]);
      }

      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<List<ContentModel>> _searchVod(List<String> queries) async {
    final List<Future<List<ContentModel>>> futures = [];
    // Leverage the user's default source preference if configured
    final sourcesToQuery = ApiService.defaultSource != null 
        ? [ApiService.defaultSource!] 
        : ApiService.sources;

    for (final q in queries) {
      for (final source in sourcesToQuery) {
        futures.add(_api.searchByTitleFromSource(q, source));
      }
    }
    final resultsList = await Future.wait(futures);
    final List<ContentModel> all = [];
    final Set<String> seen = {};
    for (final list in resultsList) {
      for (final item in list) {
        final titleKey = ApiService.normalizeText(item.title);
        if (titleKey.isNotEmpty && !seen.contains(titleKey)) {
          all.add(item);
          seen.add(titleKey);
        }
      }
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final showHistory = _controller.text.isEmpty && _results.isEmpty && !_isSearching;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search for movies, TV shows...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(LucideIcons.x, color: Colors.white70),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = [];
                  _translatedQuery = null;
                });
              },
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _performSearch,
        ),
      ),
      body: Column(
        children: [
          if (_translatedQuery != null && _results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Searching for: "$_translatedQuery" (translated from "${_controller.text}")',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),

          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  )
                : _results.isEmpty
                ? showHistory && _searchHistory.isNotEmpty
                    ? _buildHistorySection(layout)
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.search,
                              size: 64,
                              color: Colors.white12,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _controller.text.isEmpty
                                  ? 'Type to search'
                                  : 'No results found for "${_controller.text}"',
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                : GridView.builder(
                    padding: EdgeInsets.all(layout.pagePadding),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: layout.gridCount(
                        compact: 3,
                        tablet: 4,
                        desktop: 6,
                      ),
                      childAspectRatio: 0.52,
                      crossAxisSpacing: layout.isPhone ? 12 : 24,
                      mainAxisSpacing: layout.isPhone ? 16 : 32,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, i) => MovieCard(
                      content: _results[i],
                      width: null,
                      margin: EdgeInsets.zero,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ResponsiveLayout layout) {
    final padding = layout.isPhone ? 16.0 : 32.0;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      children: [
        Row(
          children: [
            const Text(
              'Recent Searches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _clearHistory,
              child: const Text(
                'Clear All',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((query) {
            return GestureDetector(
              onTap: () {
                _controller.text = query;
                _performSearch(query);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.clock, color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: layout.isPhone ? 200 : 300),
                      child: Text(
                        query,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeFromHistory(query),
                      child: const Icon(LucideIcons.x, color: AppTheme.textSecondary, size: 14),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
