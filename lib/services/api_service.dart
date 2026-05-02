import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Clear all cached content (call when language changes).
  static void clearAllCache() {
    _rawSearchCache.clear();
    _tmdbMatchCache.clear();
    final prefs = _prefs;
    if (prefs != null) {
      final keys = prefs.getKeys().where((k) => k.startsWith('cache_'));
      for (final key in keys) {
        prefs.remove(key);
      }
    }
  }

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

  static int _extractSeason(String title, String subtitle) {
    final match = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(title) 
               ?? RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(subtitle);
    if (match != null) {
      final s = match.group(1)!;
      if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s) ?? 1;
      const cnNums = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10};
      return cnNums[s] ?? 1;
    }
    final sMatch = RegExp(r'[Ss]([0-9]{1,2})').firstMatch(title) 
                ?? RegExp(r'[Ss]([0-9]{1,2})').firstMatch(subtitle);
    if (sMatch != null) {
      return int.tryParse(sMatch.group(1)!) ?? 1;
    }
    return 1;
  }

  static List<ContentModel> _groupSeasons(List<ContentModel> items) {
    final map = <String, ContentModel>{};
    for (final item in items) {
      final baseTitle = TmdbService.cleanTitle(item.title);
      final seasonNum = _extractSeason(item.title, item.subtitle);
      final updatedEpisodes = item.episodes.map((ep) {
        if (!ep.name.contains(RegExp(r'第\d+季'))) {
          return Episode(name: '第$seasonNum季 ${ep.name}', url: ep.url, imageUrl: ep.imageUrl);
        }
        return ep;
      }).toList();
      if (map.containsKey(baseTitle)) {
        final existing = map[baseTitle]!;
        map[baseTitle] = existing.copyWith(
          episodes: [...existing.episodes, ...updatedEpisodes],
          thumbnailUrl: seasonNum > _extractSeason(existing.title, existing.subtitle) 
              ? item.thumbnailUrl 
              : existing.thumbnailUrl,
        );
      } else {
        map[baseTitle] = item.copyWith(
          title: baseTitle,
          episodes: updatedEpisodes,
        );
      }
    }
    return map.values.toList();
  }

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
      final items = list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .where((c) => c.m3u8Url.isNotEmpty && c.thumbnailUrl.isNotEmpty)
          .toList();
      return _groupSeasons(items);
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

  /// Fetch raw results with pagination info: [items, pagecount, total].
  Future<(List<Map<String, dynamic>>, int, int)> _fetchRawPaged(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return (<Map<String, dynamic>>[], 0, 0);
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = body['list'] as List<dynamic>? ?? [];
      final pagecount = (body['pagecount'] as num?)?.toInt() ?? 1;
      final total = (body['total'] as num?)?.toInt() ?? 0;
      return (list.whereType<Map<String, dynamic>>().toList(), pagecount, total);
    } catch (_) {
      return (<Map<String, dynamic>>[], 0, 0);
    }
  }

  Future<List<Map<String, dynamic>>> _searchRawByTitle(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    if (_rawSearchCache.containsKey(trimmed)) return _rawSearchCache[trimmed]!;

    // Fetch all pages to get complete season coverage
    final base = '$_baseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(trimmed)}';
    final (firstPage, pagecount, _) = await _fetchRawPaged(Uri.parse(base));
    final allItems = <Map<String, dynamic>>[...firstPage];

    // Fetch remaining pages (up to 5 to avoid excessive requests)
    final maxPages = pagecount.clamp(1, 5);
    for (var pg = 2; pg <= maxPages; pg++) {
      final pageItems = await _fetchRaw(Uri.parse('$base&pg=$pg'));
      allItems.addAll(pageItems);
    }

    _rawSearchCache[trimmed] = allItems;
    return allItems;
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

    final area = (raw['vod_area'] as String? ?? '').toLowerCase();
    
    if (tmdb.mediaType == 'movie') {
      if (typeId1 == 1 || typeId == 1 || (typeId != null && typeId >= 5 && typeId <= 11)) {
        score += 20;
      } else {
        score -= 100; // Strict penalty for Movie -> Series mismatch
      }
    } else if (tmdb.mediaType == 'tv') {
      if (typeId1 == 2 || typeId == 2 || (typeId != null && typeId >= 12 && typeId <= 18)) {
        score += 20;
      } else {
        score -= 100; // Strict penalty for Series -> Movie mismatch
      }
    }

    final isProviderAnimation = typeId == 4 || typeId == 20 || genreClass.contains('\u52a8\u753b') || genreClass.contains('\u52a8\u6f2b');

    if (tmdb.genreIds.contains(16)) {
      if (isProviderAnimation) {
        score += 20;
      } else {
        score -= 100; // Strict penalty: TMDB wants Anime, Provider gave Drama/Movie
      }
    } else {
      if (isProviderAnimation) {
        score -= 100; // Strict penalty: TMDB wants Drama/Movie, Provider gave Anime
      }
    }

    switch (tmdb.originalLanguage) {
      case 'zh':
        if (tmdb.originCountries.contains('HK')) {
          if (area.contains('\u9999\u6e2f') || area.contains('\u6fb3\u95e8')) score += 20;
          else score -= 100; // Strict penalty for HK mismatch
        } else {
          if (_matchesChineseProviderMetadata(raw)) score += 20;
          else score -= 100; // Strict penalty for Chinese mismatch
        }
        break;
      case 'ko':
        if (_matchesKoreanProviderMetadata(raw)) score += 20;
        else score -= 100; // Strict penalty for Korean mismatch
        break;
      case 'en':
        if (_matchesWesternProviderMetadata(raw)) score += 20;
        else score -= 100; // Strict penalty for Western mismatch
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
    final scoredItems = <Map<String, dynamic>, int>{};

    for (final item in candidates) {
      final raw = item['raw'] as Map<String, dynamic>;
      final query = item['query'] as String;
      final score = _scoreRawMatch(raw, tmdb, query: query);
      scoredItems[raw] = score;
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
        scoredItems[raw] = score;
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

    final bestModel = _fromJson(best);
    final bestBaseTitle = TmdbService.cleanTitle(bestModel.title);
    
    final modelsToMerge = <ContentModel>[];
    for (final entry in scoredItems.entries) {
      if (entry.value >= 30) {
        final model = _fromJson(entry.key);
        if (TmdbService.cleanTitle(model.title) == bestBaseTitle) {
          modelsToMerge.add(model);
        }
      }
    }

    final grouped = _groupSeasons(modelsToMerge);
    final finalContent = grouped.isNotEmpty ? grouped.first : bestModel;

    _tmdbMatchCache[cacheKey] = finalContent;
    return finalContent;
  }

  Future<List<ContentModel>> _matchTmdbShelf(
    Future<List<TmdbResult>> tmdbFuture, {
    required int count,
    required String cacheKey,
  }) async {
    final prefs = _prefs;
    if (prefs != null) {
      final cachedJson = prefs.getString(cacheKey);
      final cacheTime = prefs.getInt('${cacheKey}_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Cache valid for 12 hours
      if (cachedJson != null && (now - cacheTime) < 12 * 60 * 60 * 1000) {
        try {
          final list = json.decode(cachedJson) as List<dynamic>;
          final cachedModels = list.map((e) => ContentModel.fromJson(e as Map<String, dynamic>)).toList();
          if (cachedModels.isNotEmpty) return cachedModels;
        } catch (_) {}
      }
    }

    final tmdbItems = await tmdbFuture;
    final matches = <ContentModel>[];
    final seenTitles = <String>{};

    const batchSize = 5;
    for (var i = 0; i < tmdbItems.length; i += batchSize) {
      final chunk = tmdbItems.skip(i).take(batchSize);
      final chunkResults = await Future.wait(
        chunk.map((tmdb) => matchTmdbToProvider(tmdb)),
      );

      for (final match in chunkResults) {
        if (match == null) continue;

        final titleKey = _normalizeText(match.title);
        if (titleKey.isEmpty || !seenTitles.add(titleKey)) continue;

        matches.add(match);
      }

      if (matches.length >= count) break;
    }

    final finalMatches = matches.take(count).toList();
    
    if (prefs != null && finalMatches.isNotEmpty) {
      prefs.setString(cacheKey, json.encode(finalMatches.map((e) => e.toJson()).toList()));
      prefs.setInt('${cacheKey}_time', DateTime.now().millisecondsSinceEpoch);
    }

    return finalMatches;
  }

  Future<List<ContentModel>> fetchMatchedTrendingMovies({
    int count = 10,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchTrendingMovies(
          count: count * 3,
        ),
        count: count,
        cacheKey: 'cache_movies_v5',
      );

  Future<List<ContentModel>> fetchMatchedTrendingTVSeries({
    int count = 10,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchTrendingTVSeries(
          count: count * 3,
        ),
        count: count,
        cacheKey: 'cache_tv_series_v5',
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
        cacheKey: 'cache_cn_dramas_v5',
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
        cacheKey: 'cache_cn_anim_v5',
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
        cacheKey: 'cache_kr_dramas_v5',
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
        cacheKey: 'cache_western_v5',
      );

  Future<List<ContentModel>> fetchMatchedRecentPopularHongKongSeries({
    int count = 10,
    int withinDays = 60,
  }) async {
    final prefs = _prefs;

    // Try TMDB-matched results first
    final tmdbMatches = await _matchTmdbShelf(
      TmdbService.fetchRecentPopularHongKongSeries(
        count: count * 3,
        withinDays: withinDays,
      ),
      count: count,
      cacheKey: 'cache_hk_series_tmdb_v7',
    );

    if (tmdbMatches.length >= count) return tmdbMatches;

    // Fallback: fetch HK/Macau dramas directly from provider
    final providerFallback = await _fetchHongKongSeriesFromProvider(count: count * 2);

    // Merge: prefer TMDB-matched, fill with provider results
    final merged = <ContentModel>[];
    final seenTitles = <String>{};
    for (final item in [...tmdbMatches, ...providerFallback]) {
      final key = _normalizeText(item.title);
      if (key.isNotEmpty && seenTitles.add(key)) {
        merged.add(item);
      }
      if (merged.length >= count) break;
    }

    // Cache merged result
    if (prefs != null && merged.isNotEmpty) {
      prefs.setString('cache_hk_series_v7', json.encode(merged.map((e) => e.toJson()).toList()));
      prefs.setInt('cache_hk_series_v7_time', DateTime.now().millisecondsSinceEpoch);
    }

    return merged;
  }

  Future<List<ContentModel>> _fetchHongKongSeriesFromProvider({int count = 20}) async {
    final prefs = _prefs;
    const cacheKey = 'cache_hk_provider_v7';

    // Check cache (6 hours)
    if (prefs != null) {
      final cachedJson = prefs.getString(cacheKey);
      final cacheTime = prefs.getInt('${cacheKey}_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (cachedJson != null && (now - cacheTime) < 6 * 60 * 60 * 1000) {
        try {
          final list = json.decode(cachedJson) as List<dynamic>;
          return list.map((e) => ContentModel.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
    }

    try {
      // type 13 = 港澳剧 (Hong Kong/Macau Drama)
      final items = await _fetch(Uri.parse('$_baseUrl?ac=videolist&t=13&pg=1'));
      final results = items.take(count).toList();

      if (prefs != null && results.isNotEmpty) {
        prefs.setString(cacheKey, json.encode(results.map((e) => e.toJson()).toList()));
        prefs.setInt('${cacheKey}_time', DateTime.now().millisecondsSinceEpoch);
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  Future<List<ContentModel>> fetchLatest({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&pg=$page'));
  Future<List<ContentModel>> fetchMovies({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=1&pg=$page'));
  Future<List<ContentModel>> fetchTVSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=2&pg=$page'));
  Future<List<ContentModel>> fetchAnimation({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=4&pg=$page'));
  Future<List<ContentModel>> fetchChineseDramas({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=12&pg=$page')); // 12 is 国产剧
  Future<List<ContentModel>> fetchHongKongSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=13&pg=$page')); // 13 is 港澳剧
  Future<List<ContentModel>> fetchKoreanDramas({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=18&pg=$page')); // 18 is 韩剧
  Future<List<ContentModel>> fetchWesternSeries({int page = 1}) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&t=15&pg=$page')); // 15 is 欧美剧

  Future<List<ContentModel>> fetchFiltered({
    int page = 1,
    int? typeId,
    String? area,
    String? year,
    String? lang,
    String? by,
  }) {
    var url = '$_baseUrl?ac=videolist&pg=$page';
    if (typeId != null) url += '&t=$typeId';
    if (area != null && area.isNotEmpty && area != 'All') url += '&area=${Uri.encodeQueryComponent(area)}';
    if (year != null && year.isNotEmpty && year != 'All') url += '&year=$year';
    if (lang != null && lang.isNotEmpty && lang != 'All') url += '&lang=${Uri.encodeQueryComponent(lang)}';
    if (by != null && by.isNotEmpty) url += '&by=$by';
    return _fetch(Uri.parse(url));
  }

  Future<List<ContentModel>> searchByTitle(String query) =>
      _fetch(Uri.parse('$_baseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(query)}'));

  // --- Multi-source support ---

  static const List<VideoSource> sources = [
    VideoSource(
      name: 'Hong Niu',
      baseUrl: 'https://www.hongniuzy2.com/api.php/provide/vod/from/hnm3u8/',
    ),
    VideoSource(
      name: 'FFZY',
      baseUrl: 'https://cj.ffzyapi.com/api.php/provide/vod/',
    ),
  ];

  Future<List<ContentModel>> searchByTitleFromSource(
      String query, VideoSource source) {
    return _fetch(Uri.parse(
        '${source.baseUrl}?ac=videolist&wd=${Uri.encodeQueryComponent(query)}'));
  }

  Future<ContentModel?> matchTmdbToProviderFromSource(
      TmdbResult tmdb, VideoSource source) async {
    final cacheKey =
        '${source.name}_${tmdb.mediaType}_${tmdb.id ?? tmdb.englishTitle}_${tmdb.year}';
    if (_tmdbMatchCache.containsKey(cacheKey)) {
      return _tmdbMatchCache[cacheKey];
    }

    final queries = _buildSearchQueries(tmdb);
    final candidates = <Map<String, dynamic>>[];
    final seen = <String>{};
    String bestQuery = queries.isNotEmpty ? queries.first : '';

    for (final q in queries) {
      final results = await _searchRawByTitleFromSource(q, source);
      for (final r in results) {
        final key =
            '${r['vod_id']}_${TmdbService.cleanTitle(r['vod_name'] as String? ?? '')}';
        if (seen.add(key)) candidates.add(r);
      }
    }

    if (candidates.isEmpty) {
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }

    Map<String, dynamic>? best;
    var bestScore = -999;
    for (final c in candidates) {
      final s = _scoreRawMatch(c, tmdb, query: bestQuery);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }

    if (bestScore < 35 && tmdb.englishTitle.isNotEmpty) {
      final chineseTitles =
          await TmdbService.findChineseTitles(tmdb.englishTitle);
      for (final ct in chineseTitles) {
        if (ct.trim().isEmpty) continue;
        final results = await _searchRawByTitleFromSource(ct, source);
        for (final r in results) {
          final key =
              '${r['vod_id']}_${TmdbService.cleanTitle(r['vod_name'] as String? ?? '')}';
          if (seen.add(key)) candidates.add(r);
          final s = _scoreRawMatch(r, tmdb, query: ct);
          if (s > bestScore) {
            bestScore = s;
            best = r;
            bestQuery = ct;
          }
        }
      }
    }

    if (best == null || bestScore < 35) {
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }

    final bestTitle =
        TmdbService.cleanTitle(best['vod_name'] as String? ?? '');
    final group = candidates
        .where((c) =>
            _scoreRawMatch(c, tmdb, query: bestQuery) >= 30 &&
            TmdbService.cleanTitle(c['vod_name'] as String? ?? '') ==
                bestTitle)
        .toList();
    if (group.length <= 1) {
      final result = _fromJson(best);
      _tmdbMatchCache[cacheKey] = result;
      return result;
    }

    final items = group
        .map((e) => _fromJson(e))
        .where((c) => c.m3u8Url.isNotEmpty && c.thumbnailUrl.isNotEmpty)
        .toList();
    final merged = _groupSeasons(items);
    final result = merged.isNotEmpty ? merged.first : null;
    _tmdbMatchCache[cacheKey] = result;
    return result;
  }

  Future<List<Map<String, dynamic>>> _searchRawByTitleFromSource(
      String title, VideoSource source) async {
    final encoded = Uri.encodeQueryComponent(title);
    final base = '${source.baseUrl}?ac=videolist&wd=$encoded';
    try {
      final (firstPage, pagecount, _) =
          await _fetchRawPaged(Uri.parse(base));
      final allItems = <Map<String, dynamic>>[...firstPage];
      final maxPages = pagecount.clamp(1, 5);
      for (var pg = 2; pg <= maxPages; pg++) {
        final pageItems = await _fetchRaw(Uri.parse('$base&pg=$pg'));
        allItems.addAll(pageItems);
      }
      return allItems;
    } catch (_) {
      return [];
    }
  }
}

class VideoSource {
  final String name;
  final String baseUrl;

  const VideoSource({required this.name, required this.baseUrl});
}
