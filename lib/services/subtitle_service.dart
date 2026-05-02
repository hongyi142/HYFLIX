import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../config/app_config.dart';

class SubtitleItem {
  final String id;
  final String fileName;
  final String language;
  final String? downloadUrl;
  final String source; // 'subdl' or 'opensubtitles'

  SubtitleItem({
    required this.id,
    required this.fileName,
    required this.language,
    this.downloadUrl,
    this.source = 'subdl',
  });
}

class SubtitleService {
  static final Map<String, List<SubtitleItem>> _cache = {};

  static String? _extractEpisodeNumber(String episodeName) {
    String cleaned = episodeName;
    cleaned = cleaned.replaceAll(RegExp(r'第\d+季\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[Ss]\d{1,2}\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[Ee][Pp]\s*'), '');
    final match = RegExp(r'(\d{1,3})').firstMatch(cleaned.trim());
    return match?.group(1);
  }

  static int? _extractSeasonFromEpisodeName(String episodeName) {
    final cnMatch = RegExp(r'第(\d+)季').firstMatch(episodeName);
    if (cnMatch != null) return int.tryParse(cnMatch.group(1)!);
    final sMatch = RegExp(r'[Ss](\d{1,2})').firstMatch(episodeName);
    if (sMatch != null) return int.tryParse(sMatch.group(1)!);
    return null;
  }

  // ─── SubDL search ───────────────────────────────────────────────
  static Future<List<SubtitleItem>> _searchSubDL({
    required String query,
    String? tmdbId,
    int? effectiveSeason,
    String? episodeNum,
    required bool isTvShow,
  }) async {
    if (subdlApiKey.isEmpty) return [];

    try {
      final queryParams = {
        'api_key': subdlApiKey,
        'languages': 'EN',
        'subs_per_page': '30',
      };

      if (tmdbId != null) {
        queryParams['tmdb_id'] = tmdbId;
      } else {
        queryParams['film_name'] = query;
      }

      if (isTvShow) {
        queryParams['type'] = 'tv';
        if (effectiveSeason != null) {
          queryParams['season_number'] = effectiveSeason.toString();
        }
        if (episodeNum != null) {
          queryParams['episode_number'] = episodeNum;
        }
      } else {
        queryParams['type'] = 'movie';
      }

      final searchUri = Uri.https('api.subdl.com', '/api/v1/subtitles', queryParams);
      print('SubDL search: $searchUri');

      final res = await http.get(searchUri).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('SubDL search failed: ${res.statusCode}');
        return [];
      }

      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['status'] == false) return [];

      final data = body['subtitles'] as List<dynamic>? ?? [];
      return data.take(15).map((item) {
        final url = (item['url'] as String?) ?? '';
        final downloadUrl = url.isNotEmpty ? 'https://dl.subdl.com$url' : null;
        final releaseName = (item['release_name'] as String?) ?? '';
        final name = (item['name'] as String?) ?? '';
        final fileName = releaseName.isNotEmpty ? releaseName : (name.isNotEmpty ? name : 'Subtitle');
        final language = (item['language'] as String?) ?? (item['lang'] as String?) ?? 'EN';

        return SubtitleItem(
          id: 'sdl_${url.hashCode}',
          fileName: fileName,
          language: language,
          downloadUrl: downloadUrl,
          source: 'subdl',
        );
      }).toList();
    } catch (e) {
      print('SubDL search error: $e');
      return [];
    }
  }

  // ─── OpenSubtitles search ───────────────────────────────────────
  static Future<List<SubtitleItem>> _searchOpenSubtitles({
    required String query,
    String? tmdbId,
    int? effectiveSeason,
    String? episodeNum,
    required bool isTvShow,
  }) async {
    if (openSubtitlesApiKey.isEmpty) return [];

    try {
      final queryParams = <String, String>{
        'languages': 'en',
      };

      if (tmdbId != null) {
        queryParams['tmdb_id'] = tmdbId;
      } else {
        queryParams['query'] = query;
      }

      if (isTvShow) {
        queryParams['type'] = 'episode';
        if (effectiveSeason != null) {
          queryParams['season_number'] = effectiveSeason.toString();
        }
        if (episodeNum != null) {
          queryParams['episode_number'] = episodeNum;
        }
      } else {
        queryParams['type'] = 'movie';
      }

      final searchUri = Uri.https('api.opensubtitles.com', '/api/v1/subtitles', queryParams);
      print('OpenSubtitles search: $searchUri');

      final res = await http.get(
        searchUri,
        headers: {
          'Api-Key': openSubtitlesApiKey,
          'Content-Type': 'application/json',
          'User-Agent': 'HYFLIX v1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('OpenSubtitles search failed: ${res.statusCode}');
        return [];
      }

      final body = json.decode(res.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>? ?? [];

      final items = <SubtitleItem>[];
      for (final entry in data.take(15)) {
        final attributes = entry['attributes'] as Map<String, dynamic>? ?? {};
        final releaseName = (attributes['release'] as String?) ?? '';
        final files = attributes['files'] as List<dynamic>? ?? [];
        final lang = attributes['language'] as String? ?? 'en';

        if (files.isEmpty) continue;
        final file = files.first as Map<String, dynamic>;
        final fileId = (file['file_id'] as num?)?.toInt();
        final fileName = releaseName.isNotEmpty ? releaseName : (file['file_name'] as String? ?? 'Subtitle');

        if (fileId == null) continue;

        items.add(SubtitleItem(
          id: 'os_$fileId',
          fileName: fileName,
          language: lang,
          downloadUrl: fileId.toString(), // Store file_id for download request
          source: 'opensubtitles',
        ));
      }

      return items;
    } catch (e) {
      print('OpenSubtitles search error: $e');
      return [];
    }
  }

  // ─── Public API ─────────────────────────────────────────────────

  static Future<List<SubtitleItem>> searchSubtitles(
    String query, {
    String? tmdbId,
    int? seasonNumber,
    String? episodeName,
    bool isTvShow = false,
  }) async {
    final effectiveSeason = seasonNumber ??
        (episodeName != null ? _extractSeasonFromEpisodeName(episodeName) : null);
    final episodeNum = episodeName != null ? _extractEpisodeNumber(episodeName) : null;
    final cacheKey = '${tmdbId ?? query}_s${effectiveSeason ?? ''}_e${episodeNum ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // Search both sources in parallel
    final results = await Future.wait([
      _searchSubDL(
        query: query,
        tmdbId: tmdbId,
        effectiveSeason: effectiveSeason,
        episodeNum: episodeNum,
        isTvShow: isTvShow,
      ),
      _searchOpenSubtitles(
        query: query,
        tmdbId: tmdbId,
        effectiveSeason: effectiveSeason,
        episodeNum: episodeNum,
        isTvShow: isTvShow,
      ),
    ]);

    final subdlItems = results[0];
    final osItems = results[1];

    // Merge: SubDL first, then OpenSubtitles, deduplicate by filename
    final merged = <SubtitleItem>[];
    final seenNames = <String>{};
    for (final item in [...subdlItems, ...osItems]) {
      final key = item.fileName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isNotEmpty && seenNames.add(key)) {
        merged.add(item);
      }
    }

    if (merged.isEmpty) {
      print('No subtitles found for $cacheKey');
    }

    _cache[cacheKey] = merged;
    return merged;
  }

  static Future<String?> fetchSubtitleContent(SubtitleItem item) async {
    if (item.downloadUrl == null) return null;

    try {
      String? downloadUrl;

      if (item.source == 'opensubtitles') {
        // OpenSubtitles: POST /download with file_id
        final fileId = item.downloadUrl!;
        final res = await http.post(
          Uri.https('api.opensubtitles.com', '/api/v1/download'),
          headers: {
            'Api-Key': openSubtitlesApiKey,
            'Content-Type': 'application/json',
            'User-Agent': 'HYFLIX v1.0',
          },
          body: json.encode({'file_id': int.tryParse(fileId) ?? fileId}),
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode != 200) {
          print('OpenSubtitles download failed: ${res.statusCode}');
          return null;
        }

        final body = json.decode(res.body) as Map<String, dynamic>;
        downloadUrl = body['link'] as String?;
        if (downloadUrl == null) return null;
      } else {
        downloadUrl = item.downloadUrl!;
      }

      print('Downloading subtitle: $downloadUrl');
      final res = await http.get(Uri.parse(downloadUrl)).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        print('Subtitle download failed: ${res.statusCode}');
        return null;
      }

      final bytes = res.bodyBytes;
      if (bytes.length < 4) return null;

      // ZIP archive
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (file.isFile && file.name.toLowerCase().endsWith('.srt')) {
            return utf8.decode(file.content as List<int>, allowMalformed: true);
          }
        }
      }
      // GZIP archive
      else if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        return utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
      }
      // Plain text
      else {
        return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      print('Subtitle download error: $e');
    }
    return null;
  }
}
