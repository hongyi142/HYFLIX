import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/content_model.dart';
import '../models/episode.dart';
import 'tmdb_service.dart';

const String _baseUrl =
    'https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static final Map<String, List<Map<String, dynamic>>> _rawSearchCache = {};
  static final Map<String, ContentModel?> _tmdbMatchCache = {};

  /// Parse ALL episodes from vod_play_url. Format: "EpName$url#EpName$url#..."
  static List<Episode> _parseEpisodes(String playUrl, {String imageUrl = ''}) {
    final episodes = <Episode>[];
    try {
      for (final part in playUrl.split('#')) {
        final trimmed = part.trim();
        final idx = trimmed.indexOf('\$');
        if (idx != -1) {
          final name = trimmed.substring(0, idx).trim();
          final url = trimmed.substring(idx + 1).trim();
          if (url.startsWith('http')) {
            episodes.add(Episode(name: name, url: url, imageUrl: imageUrl));
          }
        }
      }
    } catch (_) {}
    return episodes;
  }

  static ContentModel _fromJson(Map<String, dynamic> json) {
    final playUrl = (json['vod_play_url'] as String? ?? '');
    final pic = (json['vod_pic'] as String? ?? '').replaceAll(r'\/', '/');
    final episodes = _parseEpisodes(playUrl, imageUrl: pic);
    final m3u8 = episodes.isNotEmpty ? episodes.first.url : '';
    final score = json['vod_douban_score'];
    double rating = 0;
    if (score is String) rating = double.tryParse(score) ?? 0;
    if (score is num) rating = score.toDouble();
    final subtitle = (json['vod_remarks'] as String? ?? '');
    final blurb =
        (json['vod_blurb'] as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final titleSeed = Uri.encodeComponent(
      (json['vod_name'] as String? ?? 'movie').replaceAll(' ', '_'),
    );
    final landscapeBanner = 'https://picsum.photos/seed/$titleSeed/1920/1080';
    final year = (json['vod_year'] as String? ?? '');

    return ContentModel(
      title: json['vod_name'] as String? ?? '',
      description: blurb,
      subtitle: subtitle,
      thumbnailUrl: pic,
      bannerUrl: landscapeBanner,
      m3u8Url: m3u8,
      episodes: episodes,
      rating: rating,
      progress: 0.0,
      year: year,
    );
  }

  static String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff\uac00-\ud7af]'), '');

  static bool _containsCjk(String value) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(value);

  static bool _containsHangul(String value) =>
      RegExp(r'[\uac00-\ud7af]').hasMatch(value);

  static bool _matchesChineseProviderMetadata(Map<String, dynamic> json) {
    final area = (json['vod_area'] as String? ?? '').toLowerCase();
    final lang = (json['vod_lang'] as String? ?? '').toLowerCase();
    final genreClass = (json['vod_class'] as String? ?? '').toLowerCase();

    return area.contains('\u4e2d\u56fd') ||
        area.contains('\u5927\u9646') ||
        area.contains('\u9999\u6e2f') ||
        area.contains('\u53f0\u6e7e') ||
        lang.contains('\u6c49\u8bed') ||
        lang.contains('\u666e\u901a\u8bdd') ||
        lang.contains('\u56fd\u8bed') ||
        genreClass.contains('\u56fd\u4ea7') ||
        genreClass.contains('\u56fd\u6f2b');
  }

  static bool _matchesKoreanProviderMetadata(Map<String, dynamic> json) {
    final area = (json['vod_area'] as String? ?? '').toLowerCase();
    final lang = (json['vod_lang'] as String? ?? '').toLowerCase();
    return area.contains('\u97e9\u56fd') || lang.contains('\u97e9\u8bed');
  }

  static bool _matchesWesternProviderMetadata(Map<String, dynamic> json) {
    final area = (json['vod_area'] as String? ?? '').toLowerCase();
    final lang = (json['vod_lang'] as String? ?? '').toLowerCase();
    return area.contains('\u7f8e\u56fd') ||
        area.contains('\u82f1\u56fd') ||
        area.contains('\u52a0\u62ff\u5927') ||
        area.contains('\u6fb3\u5927\u5229\u4e9a') ||
        area.contains('\u897f\u73ed\u7259') ||
        lang.contains('\u82f1\u8bed');
  }

  Future<List<ContentModel>> _fetch(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = body['list'] as List<dynamic>? ?? [];
      return list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .where((c) => c.m3u8Url.isNotEmpty && c.thumbnailUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRaw(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = body['list'] as List<dynamic>? ?? [];
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchRawByTitle(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    if (_rawSearchCache.containsKey(trimmed)) return _rawSearchCache[trimmed]!;

    final items = await _fetchRaw(
      Uri.parse('$_baseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(trimmed)}'),
    );
    _rawSearchCache[trimmed] = items;
    return items;
  }

  List<String> _buildSearchQueries(TmdbResult tmdb) {
    final queries = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (!queries.contains(trimmed)) queries.add(trimmed);
    }

    if (tmdb.originalLanguage == 'zh') add(tmdb.originalTitle);
    add(tmdb.englishTitle);
    add(tmdb.originalTitle);

    if (_containsHangul(tmdb.originalTitle)) {
      add(tmdb.originalTitle);
    }

    return queries;
  }

  int _scoreRawMatch(
    Map<String, dynamic> raw,
    TmdbResult tmdb, {
    required String query,
  }) {
    final providerTitle = (raw['vod_name'] as String? ?? '').trim();
    final providerTitleNormalized = _normalizeText(providerTitle);
    final queryNormalized = _normalizeText(query);
    final englishNormalized = _normalizeText(tmdb.englishTitle);
    final originalNormalized = _normalizeText(tmdb.originalTitle);
    final providerYear = (raw['vod_year'] as String? ?? '').trim();
    final typeId = (raw['type_id'] as num?)?.toInt();
    final typeId1 = (raw['type_id_1'] as num?)?.toInt();
    final genreClass = (raw['vod_class'] as String? ?? '').toLowerCase();

    var score = 0;

    if (providerTitleNormalized == queryNormalized) score += 50;
    if (providerTitleNormalized == englishNormalized) score += 40;
    if (providerTitleNormalized == originalNormalized) score += 50;

    if (providerTitleNormalized.contains(queryNormalized) ||
        queryNormalized.contains(providerTitleNormalized)) {
      score += 20;
    }

    if (providerTitleNormalized.contains(originalNormalized) ||
        originalNormalized.contains(providerTitleNormalized)) {
      score += 18;
    }

    if (tmdb.year.isNotEmpty && providerYear == tmdb.year) {
      score += 15;
    }

    if (tmdb.mediaType == 'movie') {
      if (typeId1 == 1 || typeId == 1 || (typeId != null && typeId >= 5 && typeId <= 11)) {
        score += 12;
      }
    } else {
      if (typeId1 == 2 || typeId == 2 || (typeId != null && typeId >= 12 && typeId <= 18)) {
        score += 12;
      }
    }

    if (tmdb.genreIds.contains(16) && (typeId == 4 || typeId == 20 || genreClass.contains('\u52a8\u753b'))) {
      score += 12;
    }

    switch (tmdb.originalLanguage) {
      case 'zh':
        if (_matchesChineseProviderMetadata(raw)) score += 12;
        break;
      case 'ko':
        if (_matchesKoreanProviderMetadata(raw)) score += 12;
        break;
      case 'en':
        if (_matchesWesternProviderMetadata(raw)) score += 8;
        break;
    }

    return score;
  }

  Future<ContentModel?> matchTmdbToProvider(TmdbResult tmdb) async {
    final cacheKey = '${tmdb.mediaType}:${tmdb.id ?? tmdb.englishTitle}:${tmdb.year}';
    if (_tmdbMatchCache.containsKey(cacheKey)) return _tmdbMatchCache[cacheKey];

    final candidates = <Map<String, dynamic>>[];
    final seen = <String>{};

    Future<void> collectForQueries(List<String> queries) async {
      for (final query in queries) {
        final results = await _searchRawByTitle(query);
        for (final raw in results) {
          final key =
              '${raw['vod_id'] ?? ''}:${_normalizeText((raw['vod_name'] as String? ?? ''))}';
          if (!seen.add(key)) continue;
          candidates.add({
            'query': query,
            'raw': raw,
          });
        }
      }
    }

    await collectForQueries(_buildSearchQueries(tmdb));

    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final item in candidates) {
      final raw = item['raw'] as Map<String, dynamic>;
      final query = item['query'] as String;
      final score = _scoreRawMatch(raw, tmdb, query: query);
      if (score > bestScore) {
        bestScore = score;
        best = raw;
      }
    }

    if (bestScore < 35 && tmdb.englishTitle.isNotEmpty) {
      final chineseTitles = await TmdbService.findChineseTitles(tmdb.englishTitle);
      await collectForQueries(chineseTitles);

      for (final item in candidates) {
        final raw = item['raw'] as Map<String, dynamic>;
        final query = item['query'] as String;
        final score = _scoreRawMatch(raw, tmdb, query: query);
        if (score > bestScore) {
          bestScore = score;
          best = raw;
        }
      }
    }

    if (best == null || bestScore < 35) {
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }

    final content = _fromJson(best);
    _tmdbMatchCache[cacheKey] = content;
    return content;
  }

  Future<List<ContentModel>> _matchTmdbShelf(
    Future<List<TmdbResult>> tmdbFuture, {
    required int count,
  }) async {
    final tmdbItems = await tmdbFuture;
    final matches = <ContentModel>[];
    final seenTitles = <String>{};

    for (final tmdb in tmdbItems) {
      final match = await matchTmdbToProvider(tmdb);
      if (match == null) continue;

      final titleKey = _normalizeText(match.title);
      if (titleKey.isEmpty || !seenTitles.add(titleKey)) continue;

      matches.add(match);
      if (matches.length >= count) break;
    }

    return matches;
  }

  Future<List<ContentModel>> fetchMatchedRecentPopularMovies({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularMovies(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularTVSeries({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularTVSeries(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularChineseDramas({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularChineseDramas(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularChineseAnimation({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularChineseAnimation(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularKoreanDramas({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularKoreanDramas(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularWesternSeries({
    int count = 10,
    int withinDays = 60,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchRecentPopularWesternSeries(
          count: count * 3,
          withinDays: withinDays,
        ),
        count: count,
      );

  Future<List<ContentModel>> fetchLatest({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&pg=$page'));
  Future<List<ContentModel>> fetchMovies({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=1&pg=$page'));
  Future<List<ContentModel>> fetchTVSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=2&pg=$page'));
  Future<List<ContentModel>> fetchAnimation({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=4&pg=$page'));
  Future<List<ContentModel>> fetchKoreanDramas({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=18&pg=$page'));
  Future<List<ContentModel>> fetchWesternSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=15&pg=$page'));

  Future<List<ContentModel>> searchByTitle(String query) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(query)}'));
}
