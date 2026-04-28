import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../config/app_config.dart';

class SubtitleItem {
  final String id;
  final String fileName;
  final String language;
  final String? downloadUrl;

  SubtitleItem({
    required this.id,
    required this.fileName,
    required this.language,
    this.downloadUrl,
  });
}

class SubtitleService {
  static final Map<String, List<SubtitleItem>> _cache = {};

  static String? _extractEpisodeNumber(String episodeName) {
    final match = RegExp(r'(\d{1,3})').firstMatch(episodeName);
    return match?.group(1);
  }

  static Future<List<SubtitleItem>> searchSubtitles(
    String query, {
    String? tmdbId,
    int? seasonNumber,
    String? episodeName,
    bool isTvShow = false,
  }) async {
    if (subdlApiKey.isEmpty) return [];

    final episodeNum = episodeName != null ? _extractEpisodeNumber(episodeName) : null;
    final cacheKey = '${tmdbId ?? query}_s${seasonNumber ?? ''}_e${episodeNum ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

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
        if (seasonNumber != null) {
          queryParams['season_number'] = seasonNumber.toString();
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
        print('SubDL search failed: ${res.statusCode} ${res.body}');
        return [];
      }

      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['status'] == false) {
        print('SubDL error: ${body['error']}');
        return [];
      }

      final data = body['subtitles'] as List<dynamic>? ?? [];
      if (data.isEmpty) {
        print('SubDL: no subtitles for $cacheKey');
        return [];
      }

      final items = data.take(20).map((item) {
        final url = (item['url'] as String?) ?? '';
        final downloadUrl = url.isNotEmpty ? 'https://dl.subdl.com$url' : null;

        final releaseName = (item['release_name'] as String?) ?? '';
        final name = (item['name'] as String?) ?? '';
        final fileName = releaseName.isNotEmpty ? releaseName : (name.isNotEmpty ? name : 'Subtitle');
        final language = (item['language'] as String?) ?? (item['lang'] as String?) ?? 'Unknown';

        return SubtitleItem(
          id: url.hashCode.toString(),
          fileName: fileName,
          language: language,
          downloadUrl: downloadUrl,
        );
      }).toList();

      _cache[cacheKey] = items;
      return items;
    } catch (e) {
      print('SubDL search error: $e');
      return [];
    }
  }

  static Future<String?> fetchSubtitleContent(SubtitleItem item) async {
    if (item.downloadUrl == null) return null;

    try {
      print('Downloading subtitle: ${item.downloadUrl}');
      final res = await http.get(Uri.parse(item.downloadUrl!)).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        print('Subtitle download failed: ${res.statusCode} ${res.body}');
        return null;
      }

      final bytes = res.bodyBytes;
      if (bytes.length < 4) return null;

      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (file.isFile && file.name.toLowerCase().endsWith('.srt')) {
            return utf8.decode(file.content as List<int>, allowMalformed: true);
          }
        }
      } else if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        return utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
      } else {
        return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      print('Subtitle download error: $e');
    }
    return null;
  }

}
