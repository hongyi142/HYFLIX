import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import 'tmdb_service.dart';
import 'user_service.dart';

const String _baseUrl =
    'https://hhzyapi.com/api.php/provide/vod/';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static final Map<String, List<Map<String, dynamic>>> _rawSearchCache = {};
  static final Map<String, ContentModel?> _tmdbMatchCache = {};
  static SharedPreferences? _prefs;
  static VideoSource? defaultSource;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String get _activeBaseUrl => defaultSource?.baseUrl ?? _baseUrl;

  /// On web, route VOD API requests through a Netlify proxy to bypass CORS.
  static Uri _proxyUri(Uri uri) {
    if (!kIsWeb) return uri;
    final encoded = Uri.encodeComponent(uri.toString());
    return Uri.parse('/api/proxy?url=$encoded');
  }

  static void setDefaultSourceByName(String name) {
    defaultSource = sources.where((s) => s.name == name).firstOrNull;
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

  /// Parse ALL episodes from vod_play_url.
  /// Format: "EpName$url#EpName$url#..." or multi-source "group1$$$group2"
  /// where each group has the same episode format separated by #.
  static List<Episode> _parseEpisodes(String playUrl, {String imageUrl = ''}) {
    final episodes = <Episode>[];
    try {
      // Split multi-source groups (separated by $$$)
      final groups = playUrl.split(r'$$$');
      String targetGroup = groups.first;

      // Prefer direct m3u8 URLs over share page URLs
      if (groups.length > 1) {
        for (final group in groups) {
          if (group.contains('.m3u8') && !group.contains('/share/')) {
            targetGroup = group;
            break;
          }
        }
      }

      for (final part in targetGroup.split('#')) {
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

  static String normalizeText(String value) => value
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

  static bool _matchesHongKongProviderMetadata(Map<String, dynamic> json) {
    final area = (json['vod_area'] as String? ?? '').toLowerCase();
    return area.contains('香港') || area.contains('澳门') || area.contains('港');
  }

  /// Mainland = mentions 中国/大陆 or Mandarin, and is not HK/Macau-only.
  static bool _matchesMainlandProviderMetadata(Map<String, dynamic> json) {
    final area = (json['vod_area'] as String? ?? '').toLowerCase();
    final lang = (json['vod_lang'] as String? ?? '').toLowerCase();
    final mainland = area.contains('中国') ||
        area.contains('大陆') ||
        lang.contains('普通话') ||
        lang.contains('国语');
    final hongKong = _matchesHongKongProviderMetadata(json);
    return mainland && (!hongKong || area.contains('大陆'));
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
      final res = await http.get(_proxyUri(uri)).timeout(const Duration(seconds: 10));
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

  static int? _parseIntField(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchRaw(Uri uri) async {
    try {
      final res = await http.get(_proxyUri(uri)).timeout(const Duration(seconds: 10));
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
      final res = await http.get(_proxyUri(uri)).timeout(const Duration(seconds: 10));
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
    final base = '$_activeBaseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(trimmed)}';
    final (firstPage, pagecount, _) = await _fetchRawPaged(Uri.parse(base));
    final allItems = <Map<String, dynamic>>[...firstPage];

    // Fetch remaining pages (up to 5 to avoid excessive requests)
    final maxPages = pagecount.clamp(1, 2);
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
    final providerTitleNormalized = normalizeText(providerTitle);
    final queryNormalized = normalizeText(query);
    final englishNormalized = normalizeText(tmdb.englishTitle);
    final originalNormalized = normalizeText(tmdb.originalTitle);
    final providerYear = (raw['vod_year'] as String? ?? '').trim();
    final typeId = _parseIntField(raw['type_id']);
    final typeId1 = _parseIntField(raw['type_id_1']);
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
        // Region must agree with TMDB origin_country: HK \u2260 mainland.
        if (TmdbService.isHongKong(tmdb)) {
          if (_matchesHongKongProviderMetadata(raw)) score += 25;
          else score -= 100; // Strict penalty for HK mismatch
        } else if (TmdbService.isMainlandChinese(tmdb)) {
          if (_matchesMainlandProviderMetadata(raw)) score += 25;
          else if (_matchesHongKongProviderMetadata(raw)) score -= 100;
          else score -= 60;
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

    try {
      final candidates = <Map<String, dynamic>>[];
      final seen = <String>{};

      Future<void> collectForQueries(List<String> queries) async {
        final allResults = await Future.wait(
          queries.map((q) => _searchRawByTitle(q).then((r) => (q, r))),
        );
        for (final (query, results) in allResults) {
          for (final raw in results) {
            final key =
                '${raw['vod_id'] ?? ''}:${normalizeText((raw['vod_name'] as String? ?? ''))}';
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
    } catch (e) {
      debugPrint('[matchTmdbToProvider] Error matching "${tmdb.englishTitle}": $e');
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }
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
        } catch (e) {
          debugPrint('[cache] Corrupted cache "$cacheKey", clearing: $e');
          prefs.remove(cacheKey);
          prefs.remove('${cacheKey}_time');
        }
      }
    }

    try {
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

          final titleKey = normalizeText(match.title);
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
    } catch (e) {
      debugPrint('[_matchTmdbShelf] Error for "$cacheKey": $e');
      return [];
    }
  }

  Future<List<ContentModel>> fetchMatchedTrendingMovies({
    int count = 10,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchTrendingMovies(
          count: count * 3,
        ),
        count: count,
        cacheKey: 'cache_movies_v6',
      );

  Future<List<ContentModel>> fetchMatchedTrendingTVSeries({
    int count = 10,
  }) =>
      _matchTmdbShelf(
        TmdbService.fetchTrendingTVSeries(
          count: count * 3,
        ),
        count: count,
        cacheKey: 'cache_tv_series_v6',
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
        cacheKey: 'cache_cn_dramas_v6',
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
        cacheKey: 'cache_cn_anim_v6',
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
        cacheKey: 'cache_kr_dramas_v6',
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
        cacheKey: 'cache_western_v6',
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
      cacheKey: 'cache_hk_series_tmdb_v8',
    );

    if (tmdbMatches.length >= count) return tmdbMatches;

    // Fallback: fetch HK/Macau dramas directly from provider
    final providerFallback = await _fetchHongKongSeriesFromProvider(count: count * 2);

    // Merge: prefer TMDB-matched, fill with provider results
    final merged = <ContentModel>[];
    final seenTitles = <String>{};
    for (final item in [...tmdbMatches, ...providerFallback]) {
      final key = normalizeText(item.title);
      if (key.isNotEmpty && seenTitles.add(key)) {
        merged.add(item);
      }
      if (merged.length >= count) break;
    }

    // Cache merged result
    if (prefs != null && merged.isNotEmpty) {
      prefs.setString('cache_hk_series_v8', json.encode(merged.map((e) => e.toJson()).toList()));
      prefs.setInt('cache_hk_series_v8_time', DateTime.now().millisecondsSinceEpoch);
    }

    return merged;
  }

  Future<List<ContentModel>> _fetchHongKongSeriesFromProvider({int count = 20}) async {
    final prefs = _prefs;
    const cacheKey = 'cache_hk_provider_v8';

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
      // type 13 = 港澳剧 (Hong Kong/Macau Drama). Providers often file mainland
      // dramas here too, so keep only entries whose area really is HK/Macau.
      final raws = await _fetchRaw(Uri.parse('$_activeBaseUrl?ac=videolist&t=13&pg=1'));
      final items = _groupSeasons(raws
          .where(_matchesHongKongProviderMetadata)
          .where((r) => !_matchesMainlandProviderMetadata(r))
          .map(_fromJson)
          .where((c) => c.m3u8Url.isNotEmpty && c.thumbnailUrl.isNotEmpty)
          .toList());
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
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&pg=$page'));
  Future<List<ContentModel>> fetchMovies({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=1&pg=$page'));
  Future<List<ContentModel>> fetchTVSeries({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=2&pg=$page'));
  Future<List<ContentModel>> fetchAnimation({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=4&pg=$page'));
  Future<List<ContentModel>> fetchChineseDramas({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=12&pg=$page')); // 12 is 国产剧
  Future<List<ContentModel>> fetchHongKongSeries({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=13&pg=$page')); // 13 is 港澳剧
  Future<List<ContentModel>> fetchKoreanDramas({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=18&pg=$page')); // 18 is 韩剧
  Future<List<ContentModel>> fetchWesternSeries({int page = 1}) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&t=15&pg=$page')); // 15 is 欧美剧

  Future<List<ContentModel>> fetchFiltered({
    int page = 1,
    int? typeId,
    String? area,
    String? year,
    String? lang,
    String? by,
  }) {
    var url = '$_activeBaseUrl?ac=videolist&pg=$page';
    if (typeId != null) url += '&t=$typeId';
    if (area != null && area.isNotEmpty && area != 'All') url += '&area=${Uri.encodeQueryComponent(area)}';
    if (year != null && year.isNotEmpty && year != 'All') url += '&year=$year';
    if (lang != null && lang.isNotEmpty && lang != 'All') url += '&lang=${Uri.encodeQueryComponent(lang)}';
    if (by != null && by.isNotEmpty) url += '&by=$by';
    return _fetch(Uri.parse(url));
  }

  Future<List<ContentModel>> searchByTitle(String query) =>
      _fetch(Uri.parse('$_activeBaseUrl?ac=videolist&wd=${Uri.encodeQueryComponent(query)}'));

  // --- Multi-source support ---

  static const List<VideoSource> _builtInSources = [
    VideoSource(
      name: 'JSZY (Jisu)',
      baseUrl: 'https://jszyapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'BaoFeng (暴风)',
      baseUrl: 'https://bfzyapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'BDZY (Baidu)',
      baseUrl: 'https://api.apibdzy.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'HHZY (Luxury)',
      baseUrl: 'https://hhzyapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'LZI (量子)',
      baseUrl: 'https://cj.lziapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'LZCJ (量子备用)',
      baseUrl: 'https://cj.lzcaiji.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'ZUIDA (最大)',
      baseUrl: 'https://api.zuidapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'FFZY (非凡)',
      baseUrl: 'https://cj.ffzyapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'JINYING (金鹰)',
      baseUrl: 'https://www.jinyingzy.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'GUANGSU (光速)',
      baseUrl: 'https://api.guangsuapi.com/api.php/provide/vod/',
    ),
    VideoSource(
      name: 'MAOYAN (猫眼)',
      baseUrl: 'https://api.maoyanapi.top/api.php/provide/vod/',
    ),
  ];

  static final List<VideoSource> _customSources = <VideoSource>[];
  static bool _customLoaded = false;

  /// Built-in sources followed by the user's custom sources.
  static List<VideoSource> get sources =>
      List.unmodifiable([..._builtInSources, ..._customSources]);

  /// Idempotently hydrates [_customSources] from the user's saved profile.
  static Future<void> ensureCustomSourcesLoaded() async {
    if (_customLoaded) return;
    final list = await UserService.getCustomSources();
    _customSources
      ..clear()
      ..addAll(list.map(
          (m) => VideoSource(name: m['name']!, baseUrl: m['baseUrl']!)));
    _customLoaded = true;
  }

  /// Replaces the in-memory custom source list (e.g. after add/remove).
  static void setCustomSources(List<VideoSource> v) {
    _customSources
      ..clear()
      ..addAll(v);
    _customLoaded = true;
  }

  /// Probes a candidate macCMS JSON endpoint.
  /// Returns {ok, error, latencyMs, itemCount}.
  static Future<({bool ok, String? error, int latencyMs, int itemCount})>
      validateSourceUrl(String baseUrl) async {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.parse('$url?ac=list&pg=1');
    final sw = Stopwatch()..start();
    try {
      final res = await http
          .get(_proxyUri(uri))
          .timeout(const Duration(seconds: 15));
      sw.stop();
      if (res.statusCode != 200) {
        return (
          ok: false,
          error: 'HTTP ${res.statusCode}',
          latencyMs: sw.elapsedMilliseconds,
          itemCount: 0
        );
      }
      final trimmed = res.body.trim();
      if (trimmed.isEmpty || trimmed.startsWith('<')) {
        return (
          ok: false,
          error: 'Not a macCMS JSON API',
          latencyMs: sw.elapsedMilliseconds,
          itemCount: 0
        );
      }
      final decoded = json.decode(trimmed);
      if (decoded is! Map<String, dynamic> || decoded['list'] is! List) {
        return (
          ok: false,
          error: 'Not a macCMS JSON API',
          latencyMs: sw.elapsedMilliseconds,
          itemCount: 0
        );
      }
      final count = (decoded['list'] as List).length;
      if (count == 0) {
        return (
          ok: false,
          error: 'Empty catalog',
          latencyMs: sw.elapsedMilliseconds,
          itemCount: 0
        );
      }
      return (
        ok: true,
        error: null,
        latencyMs: sw.elapsedMilliseconds,
        itemCount: decoded['total'] is int
            ? decoded['total'] as int
            : int.tryParse('${decoded['total']}') ?? count
      );
    } catch (e) {
      sw.stop();
      return (
        ok: false,
        error: 'Could not reach endpoint',
        latencyMs: sw.elapsedMilliseconds,
        itemCount: 0
      );
    }
  }

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
    // Track each candidate with the query that found it
    final candidates = <Map<String, dynamic>>[];
    final seen = <String>{};

    // Run all queries in parallel instead of sequentially
    final allResults = await Future.wait(
      queries.map((q) => _searchRawByTitleFromSource(q, source).then((r) => (q, r))),
    );
    for (final (q, results) in allResults) {
      for (final r in results) {
        final key =
            '${r['vod_id']}_${TmdbService.cleanTitle(r['vod_name'] as String? ?? '')}';
        if (seen.add(key)) candidates.add({'query': q, 'raw': r});
      }
    }

    if (candidates.isEmpty) {
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }

    // Score each candidate using its own query
    final scoredItems = <Map<String, dynamic>, int>{};
    Map<String, dynamic>? best;
    var bestScore = -999;
    for (final c in candidates) {
      final raw = c['raw'] as Map<String, dynamic>;
      final q = c['query'] as String;
      final s = _scoreRawMatch(raw, tmdb, query: q);
      scoredItems[raw] = s;
      debugPrint('[SourceMatch] "${raw['vod_name']}" query="$q" score=$s');
      if (s > bestScore) {
        bestScore = s;
        best = raw;
      }
    }
    debugPrint('[SourceMatch] bestScore=$bestScore candidates=${candidates.length}');

    if (bestScore < 35 && tmdb.englishTitle.isNotEmpty) {
      final chineseTitles =
          await TmdbService.findChineseTitles(tmdb.englishTitle);
      for (final ct in chineseTitles) {
        if (ct.trim().isEmpty) continue;
        final results = await _searchRawByTitleFromSource(ct, source);
        for (final r in results) {
          final key =
              '${r['vod_id']}_${TmdbService.cleanTitle(r['vod_name'] as String? ?? '')}';
          if (seen.add(key)) candidates.add({'query': ct, 'raw': r});
          final s = _scoreRawMatch(r, tmdb, query: ct);
          scoredItems[r] = s;
          if (s > bestScore) {
            bestScore = s;
            best = r;
          }
        }
      }
    }

    if (best == null || bestScore < 35) {
      _tmdbMatchCache[cacheKey] = null;
      return null;
    }

    // Group all items with the same cleaned title (skip score threshold —
    // items already passed the bestScore >= 35 check above)
    final bestTitle =
        TmdbService.cleanTitle(best['vod_name'] as String? ?? '');
    debugPrint('[SourceMatch] bestTitle="$bestTitle"');
    final modelsToMerge = <ContentModel>[];
    for (final entry in scoredItems.entries) {
      final model = _fromJson(entry.key);
      final cleaned = TmdbService.cleanTitle(model.title);
      debugPrint('[SourceMatch]   candidate "${model.title}" cleaned="$cleaned" score=${entry.value} match=${cleaned == bestTitle}');
      if (cleaned == bestTitle) {
        modelsToMerge.add(model);
      }
    }

    debugPrint('[SourceMatch] modelsToMerge=${modelsToMerge.length}');

    if (modelsToMerge.length <= 1) {
      final result = _fromJson(best);
      debugPrint('[SourceMatch] single result, episodes=${result.episodes.length}');
      _tmdbMatchCache[cacheKey] = result;
      return result;
    }

    final merged = _groupSeasons(modelsToMerge);
    final result = merged.isNotEmpty ? merged.first : null;
    debugPrint('[SourceMatch] merged seasons, episodes=${result?.episodes.length ?? 0}');
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
      final maxPages = pagecount.clamp(1, 2);
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
