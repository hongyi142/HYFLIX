import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _results = [];
      _translatedQuery = null;
    });

    try {
      final List<String> searchQueries = [query];

      // 1. If query is English, get ALL potential Chinese names from top TMDB hits
      if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(query)) {
        final candidates = await TmdbService.findChineseTitles(query);
        if (candidates.isNotEmpty) {
          searchQueries.addAll(candidates);
          _translatedQuery = candidates.join(', ');
        }
      }

      // 2. Search Source API for ALL candidates in parallel
      final List<ContentModel> allResults = [];
      final Set<String> seenTitles = {};

      final resultsList = await Future.wait(
        searchQueries.map((q) => _api.searchByTitle(q)),
      );

      for (var list in resultsList) {
        for (var item in list) {
          if (!seenTitles.contains(item.title)) {
            allResults.add(item);
            seenTitles.add(item.title);
          }
        }
      }

      if (mounted) {
        setState(() {
          _results = allResults;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
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
              onPressed: () => _controller.clear(),
            ),
          ),
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
                ? Center(
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
}
