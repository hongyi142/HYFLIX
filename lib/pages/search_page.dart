import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/api_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/movie_card.dart';

enum _SearchFilter { all, movies, tv }

/// A search hit plus the metadata needed to rank, dedupe and filter it.
class _SearchHit {
  final ContentModel content;
  final String mediaType; // 'movie', 'tv', or '' when only known from VOD
  final int relevance;

  const _SearchHit({
    required this.content,
    required this.mediaType,
    required this.relevance,
  });
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const int _maxHistory = 20;
  static const Duration _debounceDelay = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  final ApiService _api = ApiService();

  List<_SearchHit> _hits = [];
  List<String> _searchHistory = [];
  _SearchFilter _filter = _SearchFilter.all;
  bool _isSearching = false;
  String _lastQuery = '';
  Timer? _debounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  /// Key used to collapse VOD duplicates (same show across seasons/sources).
  String _getBaseKey(String title) {
    String t = TmdbService.cleanTitle(title);
    t = t.split('：').first;
    t = t.split(':').first;
    t = t.split(' - ').first;
    t = t.replaceAll(RegExp(r'(剧场版|特别篇|OVA|SP).*', caseSensitive: false), '');
    return ApiService.normalizeText(t);
  }

  /// Scores how well a TMDB title answers the query. Exact > prefix > substring,
  /// with a small popularity nudge so well-known titles win ties.
  int _relevance(TmdbResult tmdb, String query) {
    final q = ApiService.normalizeText(query);
    var best = 0;
    for (final title in [tmdb.englishTitle, tmdb.originalTitle]) {
      final n = ApiService.normalizeText(title);
      if (n.isEmpty || q.isEmpty) continue;
      if (n == q) {
        best = math.max(best, 100);
      } else if (n.startsWith(q)) {
        best = math.max(best, 60);
      } else if (n.contains(q)) {
        best = math.max(best, 35);
      } else if (q.contains(n)) {
        best = math.max(best, 20);
      }
    }
    return best + (tmdb.voteAverage * 2).round();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      _requestId++;
      setState(() {
        _hits = [];
        _isSearching = false;
        _lastQuery = '';
      });
      return;
    }
    setState(() {});
    _debounce = Timer(_debounceDelay, () => _performSearch(value));
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    _debounce?.cancel();
    final requestId = ++_requestId;

    _saveToHistory(trimmed);
    setState(() {
      _isSearching = true;
      _lastQuery = trimmed;
    });

    try {
      final hits = await _collectHits(trimmed);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _hits = hits;
        _isSearching = false;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        setState(() => _isSearching = false);
      }
    }
  }

  /// TMDB first (rich metadata, one record per title), then VOD catalog only
  /// when TMDB has nothing. Deduped by TMDB id and by normalized title+year.
  Future<List<_SearchHit>> _collectHits(String query) async {
    final tmdbResults = await TmdbService.searchMultiple(query, maxResults: 30);
    final seenIds = <String>{};
    final seenTitles = <String>{};
    final hits = <_SearchHit>[];

    for (final tmdb in tmdbResults) {
      final idKey = '${tmdb.mediaType}:${tmdb.id}';
      final titleKey =
          '${ApiService.normalizeText(tmdb.englishTitle)}:${tmdb.year}';
      if (!seenIds.add(idKey)) continue;
      if (tmdb.englishTitle.isNotEmpty && !seenTitles.add(titleKey)) continue;
      hits.add(_SearchHit(
        content: ContentModel.fromTmdb(tmdb),
        mediaType: tmdb.mediaType,
        relevance: _relevance(tmdb, query),
      ));
    }

    if (hits.isEmpty) {
      final vod = await _searchVod(query);
      hits.addAll(vod.map((c) => _SearchHit(
            content: c,
            mediaType: '',
            relevance: 0,
          )));
    }

    hits.sort((a, b) => b.relevance.compareTo(a.relevance));
    return hits;
  }

  /// Queries every configured VOD source in parallel and collapses duplicates
  /// across sources and seasons.
  Future<List<ContentModel>> _searchVod(String query) async {
    final resultsList = await Future.wait(
      ApiService.sources.map((s) => _api.searchByTitleFromSource(query, s)),
    );
    final all = <ContentModel>[];
    final seen = <String>{};
    for (final list in resultsList) {
      for (final item in list) {
        final key = _getBaseKey(item.title);
        if (key.isNotEmpty && seen.add(key)) all.add(item);
      }
    }
    return all;
  }

  List<_SearchHit> get _visibleHits {
    switch (_filter) {
      case _SearchFilter.all:
        return _hits;
      case _SearchFilter.movies:
        return _hits.where((h) => h.mediaType == 'movie').toList();
      case _SearchFilter.tv:
        return _hits.where((h) => h.mediaType == 'tv').toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final hasQuery = _controller.text.trim().length >= 2;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Search movies, shows, anime…',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.white70),
                    onPressed: () {
                      _controller.clear();
                      _onQueryChanged('');
                    },
                  ),
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _performSearch,
        ),
      ),
      body: Column(
        children: [
          if (_hits.isNotEmpty && !_isSearching) _buildFilterChips(layout),
          Expanded(child: _buildBody(layout, hasQuery)),
        ],
      ),
    );
  }

  Widget _buildBody(ResponsiveLayout layout, bool hasQuery) {
    if (_isSearching && _hits.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    final visible = _visibleHits;
    if (visible.isEmpty) {
      if (!hasQuery && _searchHistory.isNotEmpty) {
        return _buildHistorySection(layout);
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.search, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            Text(
              !hasQuery
                  ? 'Type at least 2 characters'
                  : _hits.isEmpty
                      ? 'No results for "$_lastQuery"'
                      : 'No ${_filter == _SearchFilter.movies ? 'movies' : 'TV shows'} match "$_lastQuery"',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(layout.pagePadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: layout.gridCount(compact: 3, tablet: 4, desktop: 6),
        childAspectRatio: 0.52,
        crossAxisSpacing: layout.isPhone ? 12 : 24,
        mainAxisSpacing: layout.isPhone ? 16 : 32,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) => MovieCard(
        content: visible[i].content,
        width: null,
        margin: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildFilterChips(ResponsiveLayout layout) {
    const labels = {
      _SearchFilter.all: 'All',
      _SearchFilter.movies: 'Movies',
      _SearchFilter.tv: 'TV Shows',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 8, layout.pagePadding, 4),
      child: Wrap(
        spacing: 8,
        children: _SearchFilter.values.map((f) {
          final selected = _filter == f;
          return ChoiceChip(
            label: Text(labels[f]!),
            selected: selected,
            onSelected: (_) => setState(() => _filter = f),
            selectedColor: AppTheme.accent,
            backgroundColor: AppTheme.cardDark,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            side: BorderSide(color: selected ? AppTheme.accent : Colors.white12),
            showCheckmark: false,
          );
        }).toList(),
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
                style: TextStyle(color: AppTheme.accent, fontSize: 14),
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
                _controller.selection =
                    TextSelection.collapsed(offset: query.length);
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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeFromHistory(query),
                      child: const Icon(LucideIcons.x,
                          color: AppTheme.textSecondary, size: 14),
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
