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

  static Future<TmdbResult?> search(String title) async {
    if (tmdbApiKey.isEmpty || tmdbApiKey.contains('PASTE')) return null;

    final cacheKey = title.trim();
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final uri = Uri.https('api.themoviedb.org', '/3/search/multi', {
        'api_key': tmdbApiKey,
        'query': cacheKey,
        'language': 'en-US',
        'include_adult': 'false',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) { _cache[cacheKey] = null; return null; }

      final body = json.decode(res.body) as Map<String, dynamic>;
      final results = (body['results'] as List<dynamic>? ?? []);
      if (results.isEmpty) { _cache[cacheKey] = null; return null; }

      final withPoster = results.where((r) => r['poster_path'] != null).toList();
      final hit = withPoster.isNotEmpty ? withPoster.first : results.first;

      final genreIds = (hit['genre_ids'] as List<dynamic>? ?? [])
          .map((id) => _genreNames[id as int] ?? '')
          .where((g) => g.isNotEmpty)
          .take(3)
          .toList();

      // Extract year from release_date or first_air_date
      final dateStr = (hit['release_date'] ?? hit['first_air_date'] ?? '') as String;
      final year = dateStr.length >= 4 ? dateStr.substring(0, 4) : '';

      final result = TmdbResult(
        englishTitle: (hit['title'] ?? hit['name'] ?? title) as String,
        overview: (hit['overview'] ?? '') as String,
        posterUrl: hit['poster_path'] != null ? '$_imageBase${hit['poster_path']}' : '',
        backdropUrl: hit['backdrop_path'] != null ? '$_backdropBase${hit['backdrop_path']}' : '',
        voteAverage: ((hit['vote_average'] ?? 0) as num).toDouble(),
        year: year,
        genres: genreIds.cast<String>(),
      );

      _cache[cacheKey] = result;
      return result;
    } catch (_) {
      _cache[cacheKey] = null;
      return null;
    }
  }
}
