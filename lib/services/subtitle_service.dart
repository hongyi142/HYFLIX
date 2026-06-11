import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

enum SubtitleMatchType {
  exactEpisode,   // Filename explicitly matches the target episode
  seasonFallback, // No episode info in filename — season-level subtitle
}

extension SubtitleMatchTypeLabel on SubtitleMatchType {
  String get label => switch (this) {
    SubtitleMatchType.exactEpisode => 'Episode',
    SubtitleMatchType.seasonFallback => 'Full Season',
  };
}

class SubtitleItem {
  final String id;
  final String fileName;
  final String language;
  final String? downloadUrl;
  final String source; // 'subdl', 'opensubtitles', or 'local'
  final SubtitleMatchType matchType;
  final String? localPath; // Path to locally stored .srt file

  SubtitleItem({
    required this.id,
    required this.fileName,
    required this.language,
    this.downloadUrl,
    this.source = 'subdl',
    this.matchType = SubtitleMatchType.exactEpisode,
    this.localPath,
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

  // ─── SubDL search (with pagination) ────────────────────────────
  static Future<List<SubtitleItem>> _searchSubDL({
    required String query,
    String? tmdbId,
    int? effectiveSeason,
    String? episodeNum,
    required bool isTvShow,
  }) async {
    if (subdlApiKey.isEmpty) return [];

    try {
      final allItems = <SubtitleItem>[];
      var page = 1;
      var totalPages = 1;

      while (page <= totalPages) {
        final queryParams = {
          'api_key': subdlApiKey,
          'languages': 'EN',
          'subs_per_page': '30',
          'page': page.toString(),
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
        final res = await http.get(searchUri).timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) break;

        final body = json.decode(res.body) as Map<String, dynamic>;
        if (body['status'] == false) break;

        totalPages = (body['totalPages'] as num?)?.toInt() ?? 1;
        final data = body['subtitles'] as List<dynamic>? ?? [];

        for (final item in data) {
          final url = (item['url'] as String?) ?? '';
          final downloadUrl = url.isNotEmpty ? 'https://dl.subdl.com$url' : null;
          final releaseName = (item['release_name'] as String?) ?? '';
          final name = (item['name'] as String?) ?? '';
          final fileName = releaseName.isNotEmpty ? releaseName : (name.isNotEmpty ? name : 'Subtitle');
          final language = (item['language'] as String?) ?? (item['lang'] as String?) ?? 'EN';

          // Use API's structured fields for accurate match classification
          final apiSeason = (item['season'] as num?)?.toInt();
          final apiEpisode = (item['episode'] as num?)?.toInt();
          final apiFullSeason = item['full_season'] == true;
          final apiEpFrom = (item['episode_from'] as num?)?.toInt();
          final apiEpEnd = (item['episode_end'] as num?)?.toInt();

          allItems.add(SubtitleItem(
            id: 'sdl_${url.hashCode}',
            fileName: fileName,
            language: language,
            downloadUrl: downloadUrl,
            source: 'subdl',
            matchType: _classifyFromApiFields(
              apiSeason: apiSeason,
              apiEpisode: apiEpisode,
              apiFullSeason: apiFullSeason,
              apiEpFrom: apiEpFrom,
              apiEpEnd: apiEpEnd,
              targetSeason: effectiveSeason,
              targetEpisode: episodeNum != null ? int.tryParse(episodeNum) : null,
            ),
          ));
        }

        page++;
      }
      return allItems;
    } catch (e) {
      print('SubDL search error: $e');
      return [];
    }
  }

  /// Classify subtitle match type using API's structured metadata.
  static SubtitleMatchType _classifyFromApiFields({
    int? apiSeason,
    int? apiEpisode,
    bool apiFullSeason = false,
    int? apiEpFrom,
    int? apiEpEnd,
    int? targetSeason,
    int? targetEpisode,
  }) {
    // Full season subtitle — no specific episode
    if (apiFullSeason) return SubtitleMatchType.seasonFallback;

    // Has explicit episode info from API
    if (apiEpisode != null && targetEpisode != null) {
      if (apiEpisode == targetEpisode) return SubtitleMatchType.exactEpisode;
      return SubtitleMatchType.seasonFallback; // different episode
    }

    // Episode range (e.g., episodes 1-10)
    if (apiEpFrom != null && apiEpEnd != null && targetEpisode != null) {
      if (targetEpisode >= apiEpFrom && targetEpisode <= apiEpEnd) {
        return SubtitleMatchType.exactEpisode;
      }
      return SubtitleMatchType.seasonFallback;
    }

    // No episode info from API — season-level fallback
    return SubtitleMatchType.seasonFallback;
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

  /// Check if a subtitle filename matches the given season/episode.
  /// Returns true if the filename has no episode info (keep it) or if it matches.
  /// Returns false only if the filename explicitly references a different episode.
  static bool _matchesEpisode(String fileName, int? season, int? episode) {
    return _classifyMatch(fileName, season, episode) != null;
  }

  /// Returns [SubtitleMatchType] if the subtitle matches, or null if it
  /// explicitly references a different episode and should be excluded.
  static SubtitleMatchType? _classifyMatch(String fileName, int? season, int? episode) {
    final lower = fileName.toLowerCase();

    // Try to extract S##E## pattern
    final seMatch = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})').firstMatch(lower);
    if (seMatch != null) {
      final fileSeason = int.tryParse(seMatch.group(1)!);
      final fileEp = int.tryParse(seMatch.group(2)!);
      if (fileEp != null) {
        if (episode != null && fileEp != episode) return null;
        if (season != null && fileSeason != null && fileSeason != season) return null;
      }
      return SubtitleMatchType.exactEpisode;
    }

    // Try 1x04 pattern (season x episode)
    final xMatch = RegExp(r'(\d{1,2})[Xx](\d{1,3})').firstMatch(lower);
    if (xMatch != null) {
      final fileSeason = int.tryParse(xMatch.group(1)!);
      final fileEp = int.tryParse(xMatch.group(2)!);
      if (fileEp != null) {
        if (episode != null && fileEp != episode) return null;
        if (season != null && fileSeason != null && fileSeason != season) return null;
      }
      return SubtitleMatchType.exactEpisode;
    }

    // Try E## or EP## pattern (episode only, no season)
    final eMatch = RegExp(r'(?:^|[^a-z])(?:ep?)(\d{1,3})(?:[^a-z0-9]|$)').firstMatch(lower);
    if (eMatch != null) {
      final fileEp = int.tryParse(eMatch.group(1)!);
      if (fileEp != null && episode != null && fileEp != episode) return null;
      return SubtitleMatchType.exactEpisode;
    }

    // Try 第X季第Y集 pattern (Chinese)
    final cnMatch = RegExp(r'第\d+季第(\d+)集').firstMatch(fileName);
    if (cnMatch != null) {
      final fileEp = int.tryParse(cnMatch.group(1)!);
      if (fileEp != null && episode != null && fileEp != episode) return null;
      return SubtitleMatchType.exactEpisode;
    }

    // No episode info found in filename — keep as season fallback
    return SubtitleMatchType.seasonFallback;
  }

  // ─── Public API ─────────────────────────────────────────────────

  static Future<List<SubtitleItem>> searchSubtitles(
    String query, {
    String? tmdbId,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeName,
    bool isTvShow = false,
  }) async {
    final effectiveSeason = seasonNumber ??
        (episodeName != null ? _extractSeasonFromEpisodeName(episodeName) : null);
    final episodeNum = episodeNumber?.toString() ??
        (episodeName != null ? _extractEpisodeNumber(episodeName) : null);
    final cacheKey = '${tmdbId ?? query}_s${effectiveSeason ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // Always search by season only — most subtitle APIs don't reliably filter
    // by episode number, so we fetch all season subtitles and tag/sort client-side.
    final results = await _doSearch(
      query,
      tmdbId: tmdbId,
      effectiveSeason: effectiveSeason,
      episodeNum: episodeNum, // used for client-side tagging only
      isTvShow: isTvShow,
      sendEpisodeToApi: false,
    );

    // Fallback: no season filter if we got nothing
    if (results.isEmpty && effectiveSeason != null) {
      final fallbackKey = '${tmdbId ?? query}_';
      if (!_cache.containsKey(fallbackKey)) {
        final fallback = await _doSearch(
          query,
          tmdbId: tmdbId,
          effectiveSeason: null,
          episodeNum: episodeNum,
          isTvShow: isTvShow,
          sendEpisodeToApi: false,
        );
        _cache[fallbackKey] = fallback;
      }
      final fallbackResult = _cache[fallbackKey]!;
      _cache[cacheKey] = fallbackResult;
      return fallbackResult;
    }

    _cache[cacheKey] = results;
    return results;
  }

  static Future<List<SubtitleItem>> _doSearch(
    String query, {
    String? tmdbId,
    int? effectiveSeason,
    String? episodeNum,
    required bool isTvShow,
    bool sendEpisodeToApi = true,
  }) async {
    final apiEpisodeNum = sendEpisodeToApi ? episodeNum : null;
    final results = await Future.wait([
      _searchSubDL(
        query: query,
        tmdbId: tmdbId,
        effectiveSeason: effectiveSeason,
        episodeNum: apiEpisodeNum,
        isTvShow: isTvShow,
      ),
      _searchOpenSubtitles(
        query: query,
        tmdbId: tmdbId,
        effectiveSeason: effectiveSeason,
        episodeNum: apiEpisodeNum,
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

    // Tag all subtitles with match quality — never exclude, let the user choose
    if (effectiveSeason != null || episodeNum != null) {
      final epInt = episodeNum != null ? int.tryParse(episodeNum) : null;
      final tagged = <SubtitleItem>[];
      for (final s in merged) {
        // SubDL items already have API-based classification — keep it.
        // OpenSubtitles items need filename-based classification.
        SubtitleMatchType matchType;
        if (s.source == 'subdl') {
          matchType = s.matchType;
        } else {
          matchType = _classifyMatch(s.fileName, effectiveSeason, epInt)
              ?? SubtitleMatchType.seasonFallback;
        }
        tagged.add(SubtitleItem(
          id: s.id,
          fileName: s.fileName,
          language: s.language,
          downloadUrl: s.downloadUrl,
          source: s.source,
          matchType: matchType,
        ));
      }
      // Sort: exact episode matches first, then season fallbacks
      tagged.sort((a, b) => a.matchType.index.compareTo(b.matchType.index));
      return tagged;
    }
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

  /// Download a season-level subtitle and extract the portion for [episodeNumber].
  /// Returns the extracted SRT string, or the full SRT if extraction isn't possible.
  static Future<String?> fetchAndExtractEpisode(
    SubtitleItem item, {
    required int episodeNumber,
  }) async {
    final fullSrt = await fetchSubtitleContent(item);
    if (fullSrt == null || fullSrt.trim().isEmpty) return fullSrt;

    final entries = _parseSrt(fullSrt);
    if (entries.isEmpty) return fullSrt;

    // Check if the file spans multiple episodes (last timestamp > 100 minutes)
    final lastEndMs = entries.last.$2;
    if (lastEndMs <= 100 * 60 * 1000) {
      // Single-episode file — use as-is
      return fullSrt;
    }

    // Estimate episode duration from total file length
    final totalEpisodes = episodeNumber > 1
        ? (lastEndMs / ((episodeNumber - 1) * 60 * 1000)).ceil().clamp(episodeNumber, 30)
        : 1;
    final episodeDurationMs = (lastEndMs / totalEpisodes).round();

    final startMs = (episodeNumber - 1) * episodeDurationMs;
    final endMs = episodeNumber * episodeDurationMs;

    // Extract entries that overlap with the target episode window
    final extracted = entries
        .where((e) => e.$2 >= startMs && e.$1 <= endMs)
        .toList();

    if (extracted.isEmpty) return fullSrt; // Fallback if extraction yields nothing

    // Re-index and shift timestamps to start from 0
    final buf = StringBuffer();
    for (var i = 0; i < extracted.length; i++) {
      final (start, end, text) = extracted[i];
      buf.writeln(i + 1);
      buf.writeln('${_fmtSrt(start - startMs)} --> ${_fmtSrt(end - startMs)}');
      buf.writeln(text);
      buf.writeln();
    }
    return buf.toString();
  }

  static String _fmtSrt(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final rest = ms % 1000;
    return '${h.toString().padLeft(2, '0')}:'
           '${m.toString().padLeft(2, '0')}:'
           '${s.toString().padLeft(2, '0')},'
           '${rest.toString().padLeft(3, '0')}';
  }

  /// Parse SRT content into (startMs, endMs, text) tuples.
  static List<(int, int, String)> _parseSrt(String srt) {
    final entries = <(int, int, String)>[];
    final blocks = srt.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;
      final timeMatch = RegExp(
        r'(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})',
      ).firstMatch(lines[1]);
      if (timeMatch == null) continue;
      final start = _parseSrtTime(timeMatch.group(1)!);
      final end = _parseSrtTime(timeMatch.group(2)!);
      final text = lines.sublist(2).join('\n');
      entries.add((start, end, text));
    }
    return entries;
  }

  static int _parseSrtTime(String t) {
    final p = t.split(RegExp(r'[:,\.]'));
    return int.parse(p[0]) * 3600000 +
           int.parse(p[1]) * 60000 +
           int.parse(p[2]) * 1000 +
           int.parse(p[3]);
  }

  // ─── Local subtitle storage (native only) ───────────────────────

  static Future<Directory> _localSubsDir(String tmdbId, int season) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/subtitles/${tmdbId}_s$season');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Download a season-level ZIP, extract all SRT files, save to local storage.
  /// Returns the list of saved SubtitleItems (one per episode SRT found).
  static Future<List<SubtitleItem>> downloadSeasonSubtitles({
    required SubtitleItem item,
    required String tmdbId,
    required int season,
  }) async {
    if (item.downloadUrl == null) return [];

    try {
      final res = await http.get(Uri.parse(item.downloadUrl!))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];

      final bytes = res.bodyBytes;
      if (bytes.length < 4) return [];

      final dir = await _localSubsDir(tmdbId, season);
      final saved = <SubtitleItem>[];

      // ZIP archive
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (!file.isFile) continue;
          final name = file.name.toLowerCase();
          if (!name.endsWith('.srt')) continue;

          final srtContent = utf8.decode(file.content as List<int>, allowMalformed: true);
          final baseName = file.name.split('/').last.split('\\').last;
          final localFile = File('${dir.path}/$baseName');
          await localFile.writeAsString(srtContent);

          final matchType = _classifyMatch(baseName, season, null)
              ?? SubtitleMatchType.seasonFallback;

          saved.add(SubtitleItem(
            id: 'local_${baseName.hashCode}',
            fileName: baseName,
            language: item.language,
            source: 'local',
            matchType: matchType,
            localPath: localFile.path,
          ));
        }
      }
      // GZIP — single SRT
      else if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        final srtContent = utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
        final baseName = '${item.fileName}.srt';
        final localFile = File('${dir.path}/$baseName');
        await localFile.writeAsString(srtContent);

        saved.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: item.language,
          source: 'local',
          matchType: SubtitleMatchType.seasonFallback,
          localPath: localFile.path,
        ));
      }
      // Plain text — single SRT
      else {
        final srtContent = utf8.decode(bytes, allowMalformed: true);
        final baseName = '${item.fileName}.srt';
        final localFile = File('${dir.path}/$baseName');
        await localFile.writeAsString(srtContent);

        saved.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: item.language,
          source: 'local',
          matchType: SubtitleMatchType.seasonFallback,
          localPath: localFile.path,
        ));
      }

      return saved;
    } catch (e) {
      print('Season subtitle download error: $e');
      return [];
    }
  }

  /// Import a single .srt file from disk into local subtitle storage.
  static Future<SubtitleItem?> importLocalSubtitle({
    required String filePath,
    required String tmdbId,
    required int season,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      final baseName = filePath.split(RegExp(r'[/\\]')).last;
      final dir = await _localSubsDir(tmdbId, season);
      final destFile = File('${dir.path}/$baseName');
      await file.copy(destFile.path);

      final matchType = _classifyMatch(baseName, season, null)
          ?? SubtitleMatchType.seasonFallback;

      return SubtitleItem(
        id: 'local_${baseName.hashCode}',
        fileName: baseName,
        language: 'custom',
        source: 'local',
        matchType: matchType,
        localPath: destFile.path,
      );
    } catch (e) {
      print('Subtitle import error: $e');
      return null;
    }
  }

  /// Load all locally stored subtitles for a given tmdbId + season.
  static Future<List<SubtitleItem>> loadLocalSubtitles({
    required String tmdbId,
    required int season,
    int? episodeNumber,
  }) async {
    try {
      final dir = await _localSubsDir(tmdbId, season);
      if (!dir.existsSync()) return [];

      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.toLowerCase().endsWith('.srt'),
      );

      final items = <SubtitleItem>[];
      for (final f in files) {
        final baseName = f.path.split(RegExp(r'[/\\]')).last;
        final matchType = _classifyMatch(baseName, season, episodeNumber)
            ?? SubtitleMatchType.seasonFallback;

        items.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: 'local',
          source: 'local',
          matchType: matchType,
          localPath: f.path,
        ));
      }

      items.sort((a, b) => a.matchType.index.compareTo(b.matchType.index));
      return items;
    } catch (e) {
      print('Load local subtitles error: $e');
      return [];
    }
  }

  /// Delete all locally stored subtitles for a given tmdbId + season.
  static Future<void> deleteLocalSubtitles({
    required String tmdbId,
    required int season,
  }) async {
    try {
      final dir = await _localSubsDir(tmdbId, season);
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (e) {
      print('Delete local subtitles error: $e');
    }
  }

  /// Read the content of a locally stored subtitle file.
  /// If [episodeNumber] is provided and the file spans multiple episodes,
  /// extracts only the portion for that episode.
  static Future<String?> readLocalSubtitle(String localPath, {int? episodeNumber}) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      if (episodeNumber == null) return content;

      final entries = _parseSrt(content);
      if (entries.isEmpty) return content;

      final lastEndMs = entries.last.$2;
      if (lastEndMs <= 100 * 60 * 1000) return content;

      final totalEpisodes = episodeNumber > 1
          ? (lastEndMs / ((episodeNumber - 1) * 60 * 1000)).ceil().clamp(episodeNumber, 30)
          : 1;
      final episodeDurationMs = (lastEndMs / totalEpisodes).round();

      final startMs = (episodeNumber - 1) * episodeDurationMs;
      final endMs = episodeNumber * episodeDurationMs;

      final extracted = entries
          .where((e) => e.$2 >= startMs && e.$1 <= endMs)
          .toList();

      if (extracted.isEmpty) return content;

      final buf = StringBuffer();
      for (var i = 0; i < extracted.length; i++) {
        final (start, end, text) = extracted[i];
        buf.writeln(i + 1);
        buf.writeln('${_fmtSrt(start - startMs)} --> ${_fmtSrt(end - startMs)}');
        buf.writeln(text);
        buf.writeln();
      }
      return buf.toString();
    } catch (e) {
      print('Read local subtitle error: $e');
      return null;
    }
  }

  /// Import a ZIP file containing multiple SRTs (batch import).
  static Future<List<SubtitleItem>> importLocalSubtitleBatch({
    required String zipPath,
    required String tmdbId,
    required int season,
  }) async {
    try {
      final file = File(zipPath);
      if (!file.existsSync()) return [];

      final bytes = await file.readAsBytes();
      if (bytes.length < 4) return [];

      final dir = await _localSubsDir(tmdbId, season);
      final saved = <SubtitleItem>[];

      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          if (!entry.name.toLowerCase().endsWith('.srt')) continue;

          final srtContent = utf8.decode(entry.content as List<int>, allowMalformed: true);
          final baseName = entry.name.split('/').last.split('\\').last;
          final localFile = File('${dir.path}/$baseName');
          await localFile.writeAsString(srtContent);

          final matchType = _classifyMatch(baseName, season, null)
              ?? SubtitleMatchType.seasonFallback;

          saved.add(SubtitleItem(
            id: 'local_${baseName.hashCode}',
            fileName: baseName,
            language: 'custom',
            source: 'local',
            matchType: matchType,
            localPath: localFile.path,
          ));
        }
      }

      return saved;
    } catch (e) {
      print('Batch subtitle import error: $e');
      return [];
    }
  }
}
