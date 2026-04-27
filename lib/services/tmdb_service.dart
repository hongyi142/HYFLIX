import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Genre ID → name mapping (TMDB movie + TV combined)
const Map<int, String> _genreNames = {
  28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
  80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
  14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
  9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi', 53: 'Thriller',
  10752: 'War', 37: 'Western', 10759: 'Action & Adventure',
  10762: 'Kids', 10763: 'News', 10764: 'Reality',
  10765: 'Sci-Fi & Fantasy', 10768: 'War & Politics',
};

class TmdbResult {
  final String englishTitle;
  final String overview;
  final String posterUrl;
  final String backdropUrl;
  final double voteAverage;
  final String year;
  final List<String> genres;

  const TmdbResult({
    required this.englishTitle,
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    this.voteAverage = 0,
    this.year = '',
    this.genres = const [],
  });
}

class TmdbService {
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';
  static const String _backdropBase = 'https://image.tmdb.org/t/p/w1280';

  static final Map<String, TmdbResult?> _cache = {};

  /// Cleans titles for better TMDB matching.
  /// Removes "Season X", "Complete", "Version", etc.
  static String _cleanTitle(String title) {
    String cleaned = title;
    
    // 1. Remove Season information like "第一季", "第1季", "S01"
    cleaned = cleaned.replaceAll(RegExp(r'第[一二三四五六七八九十\d]+季'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[Ss][0-9]{1,2}'), '');
    
    // 2. Remove common suffixes
    cleaned = cleaned.replaceAll('完结', '');
    cleaned = cleaned.replaceAll('更新至', '');
    cleaned = cleaned.replaceAll('电影版', '');
    cleaned = cleaned.replaceAll('电视剧版', '');
    cleaned = cleaned.replaceAll('动漫版', '');
    cleaned = cleaned.replaceAll('版', '');
    cleaned = cleaned.replaceAll('国语', '');
    cleaned = cleaned.replaceAll('粤语', '');
    cleaned = cleaned.replaceAll('中字', '');
    
    // 3. Remove content in brackets/parentheses
    cleaned = cleaned.replaceAll(RegExp(r'[\(\[（【].*?[\)\]）】]'), '');
    
    // 4. Remove year if it's at the end
    cleaned = cleaned.replaceAll(RegExp(r'\d{4}$'), '');
    
    // 5. Trim and cleanup double spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // If we cleaned it too much and it's empty, return original
    return cleaned.isNotEmpty ? cleaned : title;
  }

  static Future<TmdbResult?> search(String title, {String? year}) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return null;

    final cleanedTitle = _cleanTitle(title);
    final cacheKey = '${cleanedTitle}_${year ?? ''}'.trim();
    
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final params = {
        'api_key': tmdbApiKey,
        'query': cleanedTitle,
        'language': 'en-US',
        'include_adult': 'false',
      };
      
      // If we have a year, passing it significantly improves accuracy
      if (year != null && year.length == 4) {
        params['year'] = year;
        params['first_air_date_year'] = year;
      }

      final uri = Uri.https('api.themoviedb.org', '/3/search/multi', params);

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) { _cache[cacheKey] = null; return null; }

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);
      if (results.isEmpty) { 
        // If search with year failed, try without year as fallback
        if (year != null) return search(title);
        _cache[cacheKey] = null; 
        return null; 
      }

      final withPoster = results.where((r) => r['poster_path'] != null).toList();
      final hit = withPoster.isNotEmpty ? withPoster.first : results.first;

      final genreIds = (hit['genre_ids'] as List<dynamic>? ?? [])
          .map((id) => _genreNames[id as int] ?? '')
          .where((g) => g.isNotEmpty)
          .take(3)
          .toList();

      final dateStr = (hit['release_date'] ?? hit['first_air_date'] ?? '') as String;
      final hitYear = dateStr.length >= 4 ? dateStr.substring(0, 4) : '';

      final result = TmdbResult(
        englishTitle: (hit['title'] ?? hit['name'] ?? title) as String,
        overview: (hit['overview'] ?? '') as String,
        posterUrl: hit['poster_path'] != null ? '$_imageBase${hit['poster_path']}' : '',
        backdropUrl: hit['backdrop_path'] != null ? '$_backdropBase${hit['backdrop_path']}' : '',
        voteAverage: ((hit['vote_average'] ?? 0) as num).toDouble(),
        year: hitYear,
        genres: genreIds.cast<String>(),
      );

      _cache[cacheKey] = result;
      return result;
    } catch (_) {
      _cache[cacheKey] = null;
      return null;
    }
  }

  /// Searches TMDB for an English title and returns potential Chinese titles
  static Future<List<String>> findChineseTitles(String englishQuery) async {
    final candidates = <String>{};
    try {
      // 1. Search for the movie/show using English query
      final searchUri = Uri.https('api.themoviedb.org', '/3/search/multi', {
        'api_key': tmdbApiKey,
        'query': englishQuery,
        'language': 'en-US',
      });

      final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode != 200) return [];

      final searchBody = json.decode(searchRes.body);
      final results = searchBody['results'] as List;
      if (results.isEmpty) return [];

      // Look at top 3 results
      for (final hit in results.take(3)) {
        final id = hit['id'];
        final mediaType = hit['media_type'];
        if (mediaType != 'movie' && mediaType != 'tv') continue;

        // Try to get Chinese name from translation list
        final transUri = Uri.https('api.themoviedb.org', '/3/$mediaType/$id/translations', {
          'api_key': tmdbApiKey,
        });

        final transRes = await http.get(transUri).timeout(const Duration(seconds: 3));
        if (transRes.statusCode == 200) {
          final transBody = json.decode(transRes.body);
          final translations = transBody['translations'] as List;
          
          for (final trans in translations) {
            final iso = trans['iso_639_1'] as String;
            if (iso == 'zh') {
              final data = trans['data'] as Map<String, dynamic>;
              final name = (data['title'] ?? data['name']) as String?;
              if (name != null && name.isNotEmpty) candidates.add(name);
            }
          }
        }
        
        // Also add the primary name if it looks Chinese
        final primaryName = (hit['title'] ?? hit['name'] ?? '') as String;
        if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(primaryName)) {
          candidates.add(primaryName);
        }
      }
    } catch (_) {}
    return candidates.toList();
  }
}
