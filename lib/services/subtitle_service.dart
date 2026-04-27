import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

class SubtitleItem {
  final String id;
  final String fileName;
  final String language;
  String? downloadUrl;

  SubtitleItem({
    required this.id,
    required this.fileName,
    required this.language,
    this.downloadUrl,
  });
}

class SubtitleService {
  static final Map<String, List<SubtitleItem>> _cache = {};

  /// Search OpenSubtitles for top subtitles.
  static Future<List<SubtitleItem>> searchSubtitles(String query, {String? tmdbId}) async {
    if (openSubtitlesApiKey.isEmpty) return [];

    final key = tmdbId ?? query.trim();
    if (_cache.containsKey(key)) return _cache[key]!;

    try {
      final headers = {
        'Api-Key': openSubtitlesApiKey,
        'Content-Type': 'application/json',
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        'X-User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
      };

      final queryParams = {
        'languages': 'en,zh-cn,zh-tw',
      };
      
      if (tmdbId != null) {
        queryParams['tmdb_id'] = tmdbId;
      } else {
        queryParams['query'] = query;
      }

      final searchUri = Uri.https('api.opensubtitles.com', '/api/v1/subtitles', queryParams);
      print('Searching subtitles with URI: $searchUri');
      
      final searchRes = await http.get(searchUri, headers: headers)
          .timeout(const Duration(seconds: 8));
      
      if (searchRes.statusCode != 200) return [];

      final searchBody = json.decode(searchRes.body) as Map<String, dynamic>;
      final data = searchBody['data'] as List<dynamic>? ?? [];
      
      final items = data.take(5).map((item) {
        final attr = item['attributes'];
        return SubtitleItem(
          id: (attr['files'] as List).first['file_id'].toString(),
          fileName: attr['release'] ?? 'Subtitle Version',
          language: attr['language'] ?? 'Unknown',
        );
      }).toList();

      _cache[key] = items;
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Downloads the subtitle content as a String
  static Future<String?> fetchSubtitleContent(SubtitleItem item) async {
    if (openSubtitlesApiKey.isEmpty) {
      print('Subtitle Error: OpenSubtitles API Key is missing.');
      return null;
    }

    try {
      final headers = {
        'Api-Key': openSubtitlesApiKey,
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        'X-User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        'Referer': 'https://www.opensubtitles.com/',
      };

      http.Response? dlRes;
      int retryCount = 0;
      
      while (retryCount < 3) {
        print('Requesting download link for File ID: ${item.id} (Attempt ${retryCount + 1})...');
        
        dlRes = await http.post(
          Uri.parse('https://api.opensubtitles.com/api/v1/download'),
          headers: headers,
          body: json.encode({'file_id': int.parse(item.id)}),
        ).timeout(const Duration(seconds: 8));

        print('Download link response status: ${dlRes.statusCode}');
        
        if (dlRes.statusCode == 503) {
          retryCount++;
          print('Server busy (503). Retrying in 3 seconds...');
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        
        break;
      }

      if (dlRes == null || dlRes.statusCode != 200) {
        if (dlRes != null) print('Download link error body: ${dlRes.body}');
        return null;
      }
      
      final dlBody = json.decode(dlRes.body) as Map<String, dynamic>;
      final link = dlBody['link'] as String?;
      if (link == null) return null;

      // 2. Download the actual file content
      print('Downloading subtitle from: $link');
      final fileRes = await http.get(Uri.parse(link)).timeout(const Duration(seconds: 10));
      if (fileRes.statusCode == 200) {
        var bytes = fileRes.bodyBytes;
        print('Downloaded ${bytes.length} bytes');
        
        // Handle GZIP
        if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
          print('GZIP detected, unzipping...');
          bytes = Uint8List.fromList(gzip.decode(bytes));
        }
        
        final content = utf8.decode(bytes, allowMalformed: true);
        print('Subtitle content preview: ${content.substring(0, content.length > 100 ? 100 : content.length)}');
        return content;
      } else {
        print('Subtitle file download failed with status: ${fileRes.statusCode}');
      }
    } catch (e) {
      print('Subtitle Service Error: $e');
    }
    return null;
  }

  /// Downloads and saves subtitle to a temporary file, returns the file path
  static Future<String?> saveSubtitleToFile(SubtitleItem item) async {
    final content = await fetchSubtitleContent(item);
    if (content == null) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/sub_${item.id}.srt');
      await file.writeAsString(content);
      return file.path;
    } catch (_) {}
    return null;
  }
}
