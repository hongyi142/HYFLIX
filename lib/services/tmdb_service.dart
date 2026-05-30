import 'dart:convert';
import 'package:flutter/foundation.dart';
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

class TmdbEpisodeInfo {
  final int episodeNumber;
  final String name;
  final String overview;
  final String? stillPath;
  final int? runtime;
  final String? airDate;

  const TmdbEpisodeInfo({
    required this.episodeNumber,
    required this.name,
    this.overview = '',
    this.stillPath,
    this.runtime,
    this.airDate,
  });

  String get stillUrl =>
      stillPath != null ? 'https://image.tmdb.org/t/p/w780$stillPath' : '';
}

class TmdbService {
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';
  static const String _backdropBase = 'https://image.tmdb.org/t/p/w1280';

  static final Map<String, TmdbResult?> _cache = {};

  /// Current language for TMDB API responses. 'en-US' or 'zh-CN'.
  static String currentLanguage = 'en-US';

  /// Set the app language and clear caches so content refetches in the new language.
  static void setLanguage(String lang) {
    currentLanguage = lang == 'zh' ? 'zh-CN' : 'en-US';
    _cache.clear();
  }

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

  /// Fetches top trending movies from TMDB for the current year.
  static Future<List<TmdbResult>> fetchTrendingMovies({int count = 8}) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    try {
      final currentYear = DateTime.now().year.toString();
      final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', {
        'api_key': tmdbApiKey,
        'language': currentLanguage,
        'sort_by': 'popularity.desc',
        'primary_release_year': currentYear,
        'include_adult': 'false',
        'include_video': 'false',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = _mapResults(
        (body['results'] as List<dynamic>? ?? []).map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          map['media_type'] = 'movie';
          return map;
        }).toList(),
      );

      return results.take(count).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches top trending TV shows from TMDB for the current year.
  static Future<List<TmdbResult>> fetchTrendingTVSeries({int count = 8}) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    try {
      final currentYear = DateTime.now().year.toString();
      final uri = Uri.https('api.themoviedb.org', '/3/discover/tv', {
        'api_key': tmdbApiKey,
        'language': currentLanguage,
        'sort_by': 'popularity.desc',
        'first_air_date_year': currentYear,
        'include_adult': 'false',
        'include_null_first_air_dates': 'false',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = _mapResults(
        (body['results'] as List<dynamic>? ?? []).map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          map['media_type'] = 'tv';
          return map;
        }).toList(),
      );

      return results.take(count).toList();
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
        'language': currentLanguage,
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
          'language': currentLanguage,
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

  /// Fetches a single page from TMDB discover API for browse use.
  /// Returns the parsed items and total available pages.
  static Future<({List<TmdbResult> items, int totalPages})> discoverBrowsePage({
    required String mediaType,
    required int page,
    Map<String, String> params = const {},
  }) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) {
      return (items: <TmdbResult>[], totalPages: 0);
    }

    try {
      final query = <String, String>{
        'api_key': tmdbApiKey,
        'language': currentLanguage,
        'include_adult': 'false',
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
      if (res.statusCode != 200) return (items: <TmdbResult>[], totalPages: 0);

      final body = json.decode(res.body) as Map<String, dynamic>;
      final totalPages = (body['total_pages'] as int?) ?? 0;
      final results = _mapResults(
        (body['results'] as List<dynamic>? ?? []).map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          map['media_type'] = mediaType;
          return map;
        }).toList(),
      );

      return (items: results, totalPages: totalPages);
    } catch (_) {
      return (items: <TmdbResult>[], totalPages: 0);
    }
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

  /// Fetch trending Chinese animations (donghua) from AniList GraphQL API.
  /// Returns TmdbResult-compatible objects for seamless pipeline integration.
  /// Uses countryOfOrigin: CN to filter for Chinese animations specifically.
  static Future<List<TmdbResult>> fetchTrendingChineseAnimationFromAniList({
    int count = 10,
  }) async {
    const query = r'''
      query ($page: Int, $perPage: Int) {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, countryOfOrigin: CN, sort: TRENDING_DESC, status_not: NOT_YET_RELEASED) {
            id
            title { romaji english native }
            description(asHtml: false)
            coverImage { large extraLarge }
            bannerImage
            averageScore
            meanScore
            popularity
            episodes
            format
            status
            startDate { year month day }
            genres
            season
            seasonYear
          }
        }
      }
    ''';

    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'query': query,
          'variables': {'page': 1, 'perPage': count},
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[AniList] HTTP ${response.statusCode}');
        return [];
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return [];

      final page = data['Page'] as Map<String, dynamic>;
      final media = page['media'] as List<dynamic>? ?? [];

      final results = <TmdbResult>[];
      for (final m in media) {
        final map = m as Map<String, dynamic>;
        final title = map['title'] as Map<String, dynamic>;
        final startDate = map['startDate'] as Map<String, dynamic>?;

        final englishTitle = (title['english'] as String?) ??
            (title['romaji'] as String?) ??
            (title['native'] as String?) ??
            '';
        final originalTitle = (title['native'] as String?) ??
            (title['romaji'] as String?) ??
            '';

        // Build poster URL from coverImage
        final coverImage = map['coverImage'] as Map<String, dynamic>?;
        final posterPath = coverImage?['extraLarge'] as String? ??
            coverImage?['large'] as String? ??
            '';
        final posterUrl = posterPath.isNotEmpty ? posterPath : '';

        final backdropUrl = (map['bannerImage'] as String?) ?? '';

        // Overview — strip HTML tags
        String overview = (map['description'] as String?) ?? '';
        overview = overview.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (overview.length > 500) overview = '${overview.substring(0, 500)}...';

        final score = (map['averageScore'] as num?)?.toDouble() ?? 0;
        final voteAverage = score > 0 ? score / 10.0 : 0.0; // AniList is 0-100, TMDB is 0-10

        final year = startDate?['year']?.toString() ??
            map['seasonYear']?.toString() ??
            '';

        final genres = (map['genres'] as List<dynamic>?)
                ?.map((g) => g.toString())
                .toList() ??
            [];

        results.add(TmdbResult(
          id: map['id'] as int?,
          englishTitle: englishTitle,
          originalTitle: originalTitle,
          overview: overview,
          posterUrl: posterUrl,
          backdropUrl: backdropUrl,
          voteAverage: voteAverage,
          year: year,
          genres: genres,
          mediaType: 'tv',
          originalLanguage: 'zh',
          originCountries: const ['CN'],
        ));
      }

      debugPrint('[AniList] Fetched ${results.length} trending Chinese animations');
      return results;
    } catch (e) {
      debugPrint('[AniList] Error: $e');
      return [];
    }
  }

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
        'language': currentLanguage,
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

  /// Fetches the Chinese title for a TMDB item by ID.
  /// Uses the TMDB details endpoint with language=zh-CN.
  static Future<String?> fetchChineseTitle(int id, String mediaType) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return null;
    try {
      final type = mediaType == 'tv' ? 'tv' : 'movie';
      final uri = Uri.https('api.themoviedb.org', '/3/$type/$id', {
        'api_key': tmdbApiKey,
        'language': 'zh-CN',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final title = (body['title'] ?? body['name'] ?? '') as String;
      return title.isNotEmpty ? title : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the IMDB ID for a TMDB item by ID.
  /// Uses the external_ids endpoint.
  static Future<String?> fetchImdbId(int tmdbId, String mediaType) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return null;
    try {
      final type = mediaType == 'tv' ? 'tv' : 'movie';
      final uri = Uri.https('api.themoviedb.org', '/3/$type/$tmdbId/external_ids', {
        'api_key': tmdbApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final imdbId = body['imdb_id'] as String?;
      return (imdbId != null && imdbId.isNotEmpty) ? imdbId : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the number of seasons for a TV show.
  static Future<int> fetchSeasonCount(int tmdbId) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return 1;
    try {
      final uri = Uri.https('api.themoviedb.org', '/3/tv/$tmdbId', {
        'api_key': tmdbApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return 1;
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (body['number_of_seasons'] as int?) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  /// Fetches the number of episodes in a given season of a TV show.
  static Future<int> fetchEpisodeCount(int tmdbId, int season) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return 0;
    try {
      final uri = Uri.https('api.themoviedb.org', '/3/tv/$tmdbId/season/$season', {
        'api_key': tmdbApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return 0;
      final body = json.decode(res.body) as Map<String, dynamic>;
      final episodes = body['episodes'] as List<dynamic>?;
      return episodes?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fetches episode details (name, overview, image) for a given season.
  static Future<List<TmdbEpisodeInfo>> fetchSeasonEpisodes(int tmdbId, int season) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];
    try {
      final uri = Uri.https('api.themoviedb.org', '/3/tv/$tmdbId/season/$season', {
        'api_key': tmdbApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final body = json.decode(res.body) as Map<String, dynamic>;
      final episodes = body['episodes'] as List<dynamic>? ?? [];
      return episodes.map((e) {
        final map = e as Map<String, dynamic>;
        return TmdbEpisodeInfo(
          episodeNumber: map['episode_number'] as int? ?? 0,
          name: map['name'] as String? ?? '',
          overview: map['overview'] as String? ?? '',
          stillPath: map['still_path'] as String?,
          runtime: map['runtime'] as int?,
          airDate: map['air_date'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches the top-billed cast names for a movie or TV show.
  static Future<List<String>> fetchCast(int id, String mediaType, {int limit = 10}) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return [];

    try {
      final type = mediaType == 'tv' ? 'tv' : 'movie';
      final uri = Uri.https('api.themoviedb.org', '/3/$type/$id/credits', {
        'api_key': tmdbApiKey,
        'language': currentLanguage,
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final cast = body['cast'] as List<dynamic>? ?? [];
      return cast
          .take(limit)
          .map((c) => (c['name'] ?? '') as String)
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Searches TMDB for an English title and returns potential Chinese titles.
  /// Translation calls run in parallel for speed.
  static Future<List<String>> findChineseTitles(String englishQuery) async {
    final candidates = <String>{};
    try {
      final searchUri = Uri.https('api.themoviedb.org', '/3/search/multi', {
        'api_key': tmdbApiKey,
        'query': englishQuery,
        'language': currentLanguage,
      });

      final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode != 200) return [];

      final searchBody = json.decode(searchRes.body);
      final results = searchBody['results'] as List;
      if (results.isEmpty) return [];

      // Collect translatable items (movies/TV only, limit to 5)
      final translatable = <(int id, String mediaType, String primaryName)>[];
      for (final hit in results.take(5)) {
        final id = hit['id'] as int?;
        final mediaType = hit['media_type'] as String?;
        final primaryName = (hit['title'] ?? hit['name'] ?? '') as String;
        if (id == null || mediaType == null || (mediaType != 'movie' && mediaType != 'tv')) continue;
        // Check if primary name is already Chinese
        if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(primaryName)) {
          candidates.add(primaryName);
        }
        translatable.add((id, mediaType, primaryName));
      }

      // Fetch all translations in parallel (was sequential \u2014 huge speedup)
      final translationFutures = translatable.map((item) async {
        final transUri = Uri.https('api.themoviedb.org', '/3/${item.$2}/${item.$1}/translations', {
          'api_key': tmdbApiKey,
        });
        try {
          final transRes = await http.get(transUri).timeout(const Duration(seconds: 3));
          if (transRes.statusCode != 200) return <String>[];
          final transBody = json.decode(transRes.body);
          final translations = transBody['translations'] as List;
          final names = <String>[];
          for (final trans in translations) {
            if (trans['iso_639_1'] == 'zh') {
              final data = trans['data'] as Map<String, dynamic>;
              final name = (data['title'] ?? data['name']) as String?;
              if (name != null && name.isNotEmpty) names.add(name);
            }
          }
          return names;
        } catch (_) {
          return <String>[];
        }
      });

      final allNames = await Future.wait(translationFutures);
      for (final names in allNames) {
        candidates.addAll(names);
      }
    } catch (_) {}
    return candidates.toList();
  }
}
