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
  final int? id;
  final String englishTitle;
  final String originalTitle;
  final String overview;
  final String posterUrl;
  final String backdropUrl;
  final double voteAverage;
  final String year;
  final List<String> genres;
  final List<int> genreIds;
  final String mediaType;
  final String originalLanguage;
  final List<String> originCountries;
  final String releaseDate;

  const TmdbResult({
    this.id,
    required this.englishTitle,
    this.originalTitle = '',
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    this.voteAverage = 0,
    this.year = '',
    this.genres = const [],
    this.genreIds = const [],
    this.mediaType = 'movie',
    this.originalLanguage = '',
    this.originCountries = const [],
    this.releaseDate = '',
  });
}

class TmdbService {
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';
  static const String _backdropBase = 'https://image.tmdb.org/t/p/w1280';

  static final Map<String, TmdbResult?> _cache = {};

  static List<TmdbResult> _mapResults(List<dynamic> results, {int? count}) {
    final mapped = results.map((hit) {
      final genreIdsRaw = (hit['genre_ids'] as List<dynamic>? ?? []);
      final genreIds = (hit['genre_ids'] as List<dynamic>? ?? [])
          .map((id) => _genreNames[id as int] ?? '')
          .where((g) => g.isNotEmpty)
          .take(3)
          .toList();

      final dateStr =
          (hit['release_date'] ?? hit['first_air_date'] ?? '') as String;
      final hitYear = dateStr.length >= 4 ? dateStr.substring(0, 4) : '';

      return TmdbResult(
        id: hit['id'] as int?,
        englishTitle: (hit['title'] ?? hit['name'] ?? '') as String,
        originalTitle:
            (hit['original_title'] ?? hit['original_name'] ?? '') as String,
        overview: (hit['overview'] ?? '') as String,
        posterUrl:
            hit['poster_path'] != null ? '$_imageBase${hit['poster_path']}' : '',
        backdropUrl: hit['backdrop_path'] != null
            ? '$_backdropBase${hit['backdrop_path']}'
            : '',
        voteAverage: ((hit['vote_average'] ?? 0) as num).toDouble(),
        year: hitYear,
        genres: genreIds.cast<String>(),
        genreIds: genreIdsRaw.whereType<int>().toList(),
        mediaType: (hit['media_type'] as String?) ??
            (hit['title'] != null ? 'movie' : 'tv'),
        originalLanguage: (hit['original_language'] ?? '') as String,
        originCountries: (hit['origin_country'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        releaseDate: dateStr,
      );
    }).toList();

    if (count == null) return mapped;
    return mapped.take(count).toList();
  }

  /// Fetches top trending movies from TMDB for the current period.
  static Future<List<TmdbResult>> fetchTrendingMovies({int count = 8}) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    try {
      final uri = Uri.https('api.themoviedb.org', '/3/trending/movie/week', {
        'api_key': tmdbApiKey,
        'language': 'en-US',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);

      return _mapResults(results, count: count);
    } catch (_) {
      return [];
    }
  }

  /// Fetches recent popular movies within the last [withinDays] days.
  static Future<List<TmdbResult>> fetchRecentPopularMovies({
    int count = 8,
    int withinDays = 60,
  }) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    try {
      final today = DateTime.now();
      final cutoff = today.subtract(Duration(days: withinDays));
      final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', {
        'api_key': tmdbApiKey,
        'language': 'en-US',
        'include_adult': 'false',
        'include_video': 'false',
        'sort_by': 'popularity.desc',
        'primary_release_date.gte': cutoff.toIso8601String().split('T').first,
        'primary_release_date.lte': today.toIso8601String().split('T').first,
        'page': '1',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);
      return _mapResults(results, count: count);
    } catch (_) {
      return [];
    }
  }

  static Future<List<TmdbResult>> _discoverMedia({
    required String mediaType,
    required Map<String, String> params,
    int count = 10,
    int maxPages = 3,
    bool Function(TmdbResult result)? predicate,
  }) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    final items = <TmdbResult>[];
    final seenIds = <int>{};

    try {
      for (int page = 1; page <= maxPages && items.length < count; page++) {
        final query = <String, String>{
          'api_key': tmdbApiKey,
          'language': 'en-US',
          'include_adult': 'false',
          'sort_by': 'popularity.desc',
          'page': '$page',
          ...params,
        };

        if (mediaType == 'movie') {
          query['include_video'] = 'false';
        } else {
          query['include_null_first_air_dates'] = 'false';
        }

        final uri = Uri.https('api.themoviedb.org', '/3/discover/$mediaType', query);
        final res = await http.get(uri).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) break;

        final body = json.decode(res.body) as Map<String, dynamic>;
        final results = _mapResults(
          (body['results'] as List<dynamic>? ?? []).map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            map['media_type'] = mediaType;
            return map;
          }).toList(),
        );

        if (results.isEmpty) break;

        for (final item in results) {
          if (item.id == null || !seenIds.add(item.id!)) continue;
          if (predicate != null && !predicate(item)) continue;
          items.add(item);
          if (items.length >= count) break;
        }
      }
    } catch (_) {
      return items;
    }

    return items;
  }

  static Map<String, String> _recentDateParams({
    required String mediaType,
    required int withinDays,
  }) {
    final today = DateTime.now();
    final cutoff = today.subtract(Duration(days: withinDays));
    final start = cutoff.toIso8601String().split('T').first;
    final end = today.toIso8601String().split('T').first;

    if (mediaType == 'movie') {
      return {
        'primary_release_date.gte': start,
        'primary_release_date.lte': end,
      };
    }

    return {
      'first_air_date.gte': start,
      'first_air_date.lte': end,
    };
  }

  static Future<List<TmdbResult>> fetchRecentPopularTVSeries({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'without_genres': '16',
        },
      );

  static Future<List<TmdbResult>> fetchRecentPopularKoreanDramas({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'with_original_language': 'ko',
          'without_genres': '16',
        },
      );

  static Future<List<TmdbResult>> fetchRecentPopularChineseDramas({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'with_original_language': 'zh',
          'without_genres': '16',
        },
      );

  static Future<List<TmdbResult>> fetchRecentPopularHongKongSeries({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'with_original_language': 'zh',
          'with_origin_country': 'HK',
          'without_genres': '16',
        },
      );

  static Future<List<TmdbResult>> fetchRecentPopularChineseAnimation({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'with_original_language': 'zh',
          'with_genres': '16',
        },
      );

  static Future<List<TmdbResult>> fetchRecentPopularWesternSeries({
    int count = 10,
    int withinDays = 60,
  }) =>
      _discoverMedia(
        mediaType: 'tv',
        count: count,
        params: {
          ..._recentDateParams(mediaType: 'tv', withinDays: withinDays),
          'with_original_language': 'en',
          'without_genres': '16',
        },
        predicate: (item) {
          if (item.originCountries.isEmpty) return true;
          const western = {'US', 'GB', 'CA', 'AU', 'NZ', 'IE'};
          return item.originCountries.any(western.contains);
        },
      );

  /// Cleans titles for better TMDB matching.
  /// Removes "Season X", "Complete", "Version", etc.
  static String cleanTitle(String title) {
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

    final cleanedTitle = cleanTitle(title);
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
        id: hit['id'] as int?,
        englishTitle: (hit['title'] ?? hit['name'] ?? title) as String,
        originalTitle:
            (hit['original_title'] ?? hit['original_name'] ?? title) as String,
        overview: (hit['overview'] ?? '') as String,
        posterUrl: hit['poster_path'] != null ? '$_imageBase${hit['poster_path']}' : '',
        backdropUrl: hit['backdrop_path'] != null ? '$_backdropBase${hit['backdrop_path']}' : '',
        voteAverage: ((hit['vote_average'] ?? 0) as num).toDouble(),
        year: hitYear,
        genres: genreIds.cast<String>(),
        genreIds: (hit['genre_ids'] as List<dynamic>? ?? []).whereType<int>().toList(),
        mediaType: (hit['media_type'] as String?) ??
            (hit['title'] != null ? 'movie' : 'tv'),
        originalLanguage: (hit['original_language'] ?? '') as String,
        originCountries: (hit['origin_country'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        releaseDate: dateStr,
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
