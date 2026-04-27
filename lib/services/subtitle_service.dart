import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class SubtitleService {
  static final Map<String, String?> _cache = {};

  /// Search OpenSubtitles for an English SRT and return the download URL.
  /// Returns null if no key is set or no subtitle is found.
  static Future<String?> getSubtitleUrl(String title) async {
    if (openSubtitlesApiKey.isEmpty) return null;

    final key = title.trim();
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final headers = {
        'Api-Key': openSubtitlesApiKey,
        'Content-Type': 'application/json',
        'User-Agent': 'HYFLIX v1.0',
      };

      // Step 1: Search
      final searchUri = Uri.https('api.opensubtitles.com', '/api/v1/subtitles', {
        'query': key,
        'languages': 'en',
        'type': 'movie',
      });
      final searchRes = await http.get(searchUri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (searchRes.statusCode != 200) { _cache[key] = null; return null; }

      final searchBody = json.decode(searchRes.body) as Map<String, dynamic>;
      final data = searchBody['data'] as List<dynamic>? ?? [];
      if (data.isEmpty) { _cache[key] = null; return null; }

      final fileId = (data.first['attributes']['files'] as List).first['file_id'];

      // Step 2: Get download link
      final dlRes = await http.post(
        Uri.parse('https://api.opensubtitles.com/api/v1/download'),
        headers: headers,
        body: json.encode({'file_id': fileId}),
      ).timeout(const Duration(seconds: 8));
      if (dlRes.statusCode != 200) { _cache[key] = null; return null; }

      final dlBody = json.decode(dlRes.body) as Map<String, dynamic>;
      final link = dlBody['link'] as String?;
      _cache[key] = link;
      return link;
    } catch (_) {
      _cache[key] = null;
      return null;
    }
  }
}
