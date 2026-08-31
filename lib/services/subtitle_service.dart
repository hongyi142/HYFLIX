import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../config/app_config.dart';
import 'subtitle_storage.dart';

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
    required String fileName,
    required this.language,
    this.downloadUrl,
    this.source = 'subdl',
    this.matchType = SubtitleMatchType.exactEpisode,
    this.localPath,
  }) : fileName = SubtitleService.normalizeUnicodeAlphanumeric(fileName);
}

class SubtitleService {
  static final Map<String, List<SubtitleItem>> _cache = {};

  static String normalizeUnicodeAlphanumeric(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      var char = rune;
      // Map mathematical capital letters (A-Z)
      if (rune >= 0x1D400 && rune <= 0x1D419) char = rune - 0x1D400 + 0x41;
      else if (rune >= 0x1D434 && rune <= 0x1D44D) char = rune - 0x1D434 + 0x41;
      else if (rune >= 0x1D468 && rune <= 0x1D481) char = rune - 0x1D468 + 0x41;
      else if (rune >= 0x1D5A0 && rune <= 0x1D5B9) char = rune - 0x1D5A0 + 0x41;
      else if (rune >= 0x1D5D4 && rune <= 0x1D5ED) char = rune - 0x1D5D4 + 0x41;
      else if (rune >= 0x1D608 && rune <= 0x1D621) char = rune - 0x1D608 + 0x41;
      else if (rune >= 0x1D63C && rune <= 0x1D655) char = rune - 0x1D63C + 0x41;
      else if (rune >= 0x1D670 && rune <= 0x1D689) char = rune - 0x1D670 + 0x41;
      // Map mathematical lowercase letters (a-z)
      else if (rune >= 0x1D41A && rune <= 0x1D433) char = rune - 0x1D41A + 0x61;
      else if (rune >= 0x1D44E && rune <= 0x1D467) char = rune - 0x1D44E + 0x61;
      else if (rune >= 0x1D482 && rune <= 0x1D49B) char = rune - 0x1D482 + 0x61;
      else if (rune >= 0x1D5BA && rune <= 0x1D5D3) char = rune - 0x1D5BA + 0x61;
      else if (rune >= 0x1D5EE && rune <= 0x1D607) char = rune - 0x1D5EE + 0x61;
      else if (rune >= 0x1D622 && rune <= 0x1D63B) char = rune - 0x1D622 + 0x61;
      else if (rune >= 0x1D656 && rune <= 0x1D66F) char = rune - 0x1D656 + 0x61;
      else if (rune >= 0x1D68A && rune <= 0x1D6A3) char = rune - 0x1D68A + 0x61;
      // Map mathematical digits (0-9)
      else if (rune >= 0x1D7CE && rune <= 0x1D7D7) char = rune - 0x1D7CE + 0x30;
      else if (rune >= 0x1D7D8 && rune <= 0x1D7E1) char = rune - 0x1D7D8 + 0x30;
      else if (rune >= 0x1D7E2 && rune <= 0x1D7EB) char = rune - 0x1D7E2 + 0x30;
      else if (rune >= 0x1D7EC && rune <= 0x1D7F5) char = rune - 0x1D7EC + 0x30; // 𝟬-𝟵
      else if (rune >= 0x1D7F6 && rune <= 0x1D7FF) char = rune - 0x1D7F6 + 0x30;
      buffer.writeCharCode(char);
    }
    return buffer.toString();
  }

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

  static String? _extractEpisodeFromQuery(String text) {
    final sEpMatch = RegExp(r'[Ss]\d{1,2}[Ee](\d{1,3})', caseSensitive: false).firstMatch(text);
    if (sEpMatch != null) return int.tryParse(sEpMatch.group(1)!)?.toString();
    final epMatch = RegExp(r'\b[Ee](\d{1,3})\b', caseSensitive: false).firstMatch(text);
    if (epMatch != null) return int.tryParse(epMatch.group(1)!)?.toString();
    return _extractEpisodeNumber(text);
  }

  static String normalizeLanguage(String lang) {
    final lower = lang.toLowerCase().trim();
    if (lower == 'zh' ||
        lower == 'zh-cn' ||
        lower == 'zh-tw' ||
        lower == 'zh-hk' ||
        lower == 'chinese' ||
        lower == 'chi' ||
        lower == 'cn' ||
        lower == 'tc' ||
        lower == 'sc') {
      return 'ZH';
    }
    if (lower == 'en' || lower == 'eng' || lower == 'english') {
      return 'EN';
    }
    return lang.toUpperCase();
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

      while (page <= (episodeNum != null ? 1 : totalPages)) {
        final queryParams = {
          'api_key': subdlApiKey,
          'languages': 'EN,ZH,ZH-CN,ZH-TW,CHI,CN',
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
        print('[SubDL] Requesting: $searchUri');
        final res = await http.get(searchUri).timeout(const Duration(seconds: 10));
        print('[SubDL] Response Code: ${res.statusCode}');
        print('[SubDL] Response Body: ${res.body.substring(0, res.body.length > 500 ? 500 : res.body.length)}...');

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
          final rawLanguage = (item['language'] as String?) ?? (item['lang'] as String?) ?? (item['language_code'] as String?) ?? 'EN';
          final language = normalizeLanguage(rawLanguage);

          // Use API's structured fields for accurate match classification
          final apiSeason = (item['season'] as num?)?.toInt();
          final apiEpisode = (item['episode'] as num?)?.toInt();
          final apiFullSeason = item['full_season'] == true;
          final apiEpFrom = (item['episode_from'] as num?)?.toInt();
          final apiEpEnd = (item['episode_end'] as num?)?.toInt();

          final matchType = _classifyFromApiFields(
            apiSeason: apiSeason,
            apiEpisode: apiEpisode,
            apiFullSeason: apiFullSeason,
            apiEpFrom: apiEpFrom,
            apiEpEnd: apiEpEnd,
            targetSeason: effectiveSeason,
            targetEpisode: episodeNum != null ? int.tryParse(episodeNum) : null,
          );

          // Skip if query was for a specific episode and this subtitle belongs to another episode
          if (episodeNum != null && matchType == null) {
            continue;
          }

          allItems.add(SubtitleItem(
            id: 'sdl_${url.hashCode}',
            fileName: fileName,
            language: language,
            downloadUrl: downloadUrl,
            source: 'subdl',
            matchType: matchType ?? SubtitleMatchType.seasonFallback,
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
  static SubtitleMatchType? _classifyFromApiFields({
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
      return null; // different episode
    }

    // Episode range (e.g., episodes 1-10)
    if (apiEpFrom != null && apiEpEnd != null && targetEpisode != null) {
      if (targetEpisode >= apiEpFrom && targetEpisode <= apiEpEnd) {
        return SubtitleMatchType.exactEpisode;
      }
      return null; // different episode range
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
        'languages': 'en,zh,zh-cn,zh-tw',
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
        final rawLang = attributes['language'] as String? ?? 'en';
        final lang = normalizeLanguage(rawLang);

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
    return classifyMatch(fileName, season, episode) != null;
  }

  /// Returns [SubtitleMatchType] if the subtitle matches, or null if it
  /// explicitly references a different episode and should be excluded.
  static SubtitleMatchType? classifyMatch(String fileName, int? season, int? episode) {
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

    // Try matching standalone numbers (e.g. "01.srt", "Show Name - 01.srt", "Show.Name.01.srt")
    // Avoid matching resolutions (720, 1080, 2160) or years (19xx, 20xx) or video codecs (264, 265)
    final numMatch = RegExp(r'(?:^|[^0-9a-zA-Z])(\d{1,3})(?:\.srt|\.ass|\b|$)').firstMatch(lower);
    if (numMatch != null) {
      final fileEp = int.tryParse(numMatch.group(1)!);
      if (fileEp != null) {
        if (fileEp == 720 || fileEp == 1080 || fileEp == 2160 || fileEp == 480 || fileEp == 576 || (fileEp >= 1900 && fileEp <= 2100) || fileEp == 264 || fileEp == 265) {
          // Ignore false positive resolutions, years, and codecs
        } else {
          if (episode != null && fileEp != episode) return null;
          return SubtitleMatchType.exactEpisode;
        }
      }
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
    bool searchFullSeason = false,
  }) async {
    final effectiveSeason = seasonNumber ??
        (episodeName != null ? _extractSeasonFromEpisodeName(episodeName) : _extractSeasonFromEpisodeName(query));
    final episodeNum = episodeNumber?.toString() ??
        (episodeName != null ? _extractEpisodeNumber(episodeName) : _extractEpisodeFromQuery(query));
    print('[SubtitleService] searchSubtitles entry: query="$query", tmdbId=$tmdbId, season=$seasonNumber, episode=$episodeNumber, effectiveSeason=$effectiveSeason, episodeNum=$episodeNum, searchFullSeason=$searchFullSeason');
    
    final cacheKey = searchFullSeason
        ? '${tmdbId ?? query}_s${effectiveSeason ?? ''}_all'
        : '${tmdbId ?? query}_s${effectiveSeason ?? ''}_e${episodeNum ?? ''}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    // If searchFullSeason is false and episodeNum is available, query API for this specific episode only.
    // If searchFullSeason is true, fetch all subtitles for the season.
    final results = await _doSearch(
      query,
      tmdbId: tmdbId,
      effectiveSeason: effectiveSeason,
      episodeNum: episodeNum,
      isTvShow: isTvShow,
      sendEpisodeToApi: !searchFullSeason && episodeNum != null,
    );

    // Fallback: if full season search was requested and gave nothing, try without season filter
    if (results.isEmpty && effectiveSeason != null && searchFullSeason) {
      final fallbackKey = '${tmdbId ?? query}_all';
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
    print('[SubtitleService] _doSearch: SubDL returned ${subdlItems.length} items, OS returned ${osItems.length} items');

    // Merge: SubDL first, then OpenSubtitles, deduplicate by filename
    final merged = <SubtitleItem>[];
    final seenKeys = <String>{};
    for (final item in [...subdlItems, ...osItems]) {
      var key = item.fileName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (key.isEmpty) {
        key = item.fileName.toLowerCase().trim();
      }
      if (key.isNotEmpty && seenKeys.add(key)) {
        merged.add(item);
      }
    }

    // Tag all subtitles with match quality
    if (effectiveSeason != null || episodeNum != null) {
      final epInt = episodeNum != null ? int.tryParse(episodeNum) : null;
      final tagged = <SubtitleItem>[];
      for (final s in merged) {
        // SubDL items already have API-based classification.
        // OpenSubtitles items need filename-based classification.
        SubtitleMatchType? matchType = s.matchType;
        if (s.source == 'subdl' && matchType == SubtitleMatchType.seasonFallback) {
          final filenameMatch = classifyMatch(s.fileName, effectiveSeason, epInt);
          if (filenameMatch != null) {
            matchType = filenameMatch;
          } else if (sendEpisodeToApi && epInt != null) {
            // Filename explicitly mentions a different episode — skip in single-episode mode
            continue;
          }
        } else if (s.source != 'subdl') {
          final filenameMatch = classifyMatch(s.fileName, effectiveSeason, epInt);
          if (filenameMatch != null) {
            matchType = filenameMatch;
          } else if (sendEpisodeToApi && epInt != null) {
            // Explicitly wrong episode — skip in single-episode mode
            continue;
          } else {
            matchType = SubtitleMatchType.seasonFallback;
          }
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

  /// Helper to check if a file extension is a supported subtitle format (.srt, .ass, .ssa, .vtt)
  static bool isSupportedSubtitleFile(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.srt') ||
        lower.endsWith('.ass') ||
        lower.endsWith('.ssa') ||
        lower.endsWith('.vtt');
  }

  /// Convert subtitle text from ASS, SSA, or VTT format to clean SRT format.
  /// If the text is already SRT, it is returned unmodified.
  static String convertToSrt(String content, {String? fileName}) {
    final lowerName = (fileName ?? '').toLowerCase();
    if (lowerName.endsWith('.ass') ||
        lowerName.endsWith('.ssa') ||
        content.contains('[Events]') ||
        content.contains('[Script Info]')) {
      final srt = _assToSrt(content);
      if (srt.isNotEmpty) return srt;
    } else if (lowerName.endsWith('.vtt') || content.trimLeft().startsWith('WEBVTT')) {
      final srt = _vttToSrt(content);
      if (srt.isNotEmpty) return srt;
    }
    return content;
  }

  /// Convert ASS / SSA subtitle format to SRT format
  static String _assToSrt(String assContent) {
    final lines = assContent.split(RegExp(r'\r?\n'));
    bool eventsFound = false;
    Map<String, int> formatIndices = {};
    final srtEntries = <(String, String, String)>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.toLowerCase().startsWith('[events]')) {
        eventsFound = true;
        continue;
      }
      if (!eventsFound) continue;

      if (line.toLowerCase().startsWith('format:')) {
        final headers = line.substring(7).split(',').map((h) => h.trim().toLowerCase()).toList();
        formatIndices = {for (var i = 0; i < headers.length; i++) headers[i]: i};
        continue;
      }

      if (line.toLowerCase().startsWith('dialogue:')) {
        final commaCount = formatIndices.isNotEmpty ? formatIndices.length - 1 : 9;
        // Split with limit to preserve commas in the dialogue text
        final parts = _splitDialogue(line.substring(9).trim(), commaCount);
        if (parts.isEmpty) continue;

        String startRaw;
        String endRaw;
        String textRaw;

        if (formatIndices.containsKey('start') &&
            formatIndices.containsKey('end') &&
            formatIndices.containsKey('text') &&
            parts.length > formatIndices['text']!) {
          startRaw = parts[formatIndices['start']!].trim();
          endRaw = parts[formatIndices['end']!].trim();
          textRaw = parts[formatIndices['text']!].trim();
        } else if (parts.length >= 10) {
          startRaw = parts[1].trim();
          endRaw = parts[2].trim();
          textRaw = parts[9].trim();
        } else if (parts.length >= 3) {
          startRaw = parts[1].trim();
          endRaw = parts[2].trim();
          textRaw = parts.last.trim();
        } else {
          continue;
        }

        final startSrt = _formatAssTimeToSrt(startRaw);
        final endSrt = _formatAssTimeToSrt(endRaw);

        // Strip ASS style overrides (e.g. {\an8}, {\pos(x,y)}, {\c&H...&})
        var cleanText = textRaw.replaceAll(RegExp(r'\{.*?\}'), '');
        // Replace ASS line breaks
        cleanText = cleanText
            .replaceAll(r'\N', '\n')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\h', ' ')
            .trim();

        if (cleanText.isNotEmpty) {
          srtEntries.add((startSrt, endSrt, cleanText));
        }
      }
    }

    if (srtEntries.isEmpty) return '';

    final buf = StringBuffer();
    for (var i = 0; i < srtEntries.length; i++) {
      final (s, e, txt) = srtEntries[i];
      buf.writeln(i + 1);
      buf.writeln('$s --> $e');
      buf.writeln(txt);
      buf.writeln();
    }
    return buf.toString();
  }

  /// Split ASS Dialogue line by up to [limit] commas
  static List<String> _splitDialogue(String line, int limit) {
    final result = <String>[];
    var current = StringBuffer();
    var count = 0;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == ',' && count < limit) {
        result.add(current.toString());
        current = StringBuffer();
        count++;
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  /// Convert ASS timestamp (H:MM:SS.cs or H:MM:SS.ms) to SRT format (HH:MM:SS,mmm)
  static String _formatAssTimeToSrt(String t) {
    final parts = t.split(':');
    if (parts.length < 3) return '00:00:00,000';

    final h = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final m = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    final secParts = parts[2].split('.');
    final s = (int.tryParse(secParts[0]) ?? 0).toString().padLeft(2, '0');
    final csStr = secParts.length > 1 ? secParts[1] : '0';
    final ms = int.tryParse(csStr.padRight(3, '0').substring(0, 3)) ?? 0;
    final msStr = ms.toString().padLeft(3, '0');

    return '$h:$m:$s,$msStr';
  }

  /// Convert WebVTT format to SRT format
  static String _vttToSrt(String vttContent) {
    final lines = vttContent.split(RegExp(r'\r?\n'));
    final srtEntries = <(String, String, String)>[];
    var i = 0;

    final timeRegex = RegExp(r'(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})');

    while (i < lines.length) {
      final line = lines[i].trim();
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final sh = (match.group(1) ?? '00').padLeft(2, '0');
        final sm = match.group(2)!.padLeft(2, '0');
        final ss = match.group(3)!.padLeft(2, '0');
        final sms = match.group(4)!;

        final eh = (match.group(5) ?? '00').padLeft(2, '0');
        final em = match.group(6)!.padLeft(2, '0');
        final es = match.group(7)!.padLeft(2, '0');
        final ems = match.group(8)!;

        final startSrt = '$sh:$sm:$ss,$sms';
        final endSrt = '$eh:$em:$es,$ems';

        i++;
        final textLines = <String>[];
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          // Strip HTML / WebVTT cue tags (<v Narrator>, <b>, etc.)
          final clean = lines[i].replaceAll(RegExp(r'<[^>]+>'), '').trim();
          if (clean.isNotEmpty) {
            textLines.add(clean);
          }
          i++;
        }

        if (textLines.isNotEmpty) {
          srtEntries.add((startSrt, endSrt, textLines.join('\n')));
        }
      } else {
        i++;
      }
    }

    if (srtEntries.isEmpty) return '';

    final buf = StringBuffer();
    for (var idx = 0; idx < srtEntries.length; idx++) {
      final (s, e, txt) = srtEntries[idx];
      buf.writeln(idx + 1);
      buf.writeln('$s --> $e');
      buf.writeln(txt);
      buf.writeln();
    }
    return buf.toString();
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
            'Accept': 'application/json',
            'User-Agent': 'HYFLIX v1.0',
          },
          body: json.encode({'file_id': int.tryParse(fileId) ?? fileId}),
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode != 200) {
          print('OpenSubtitles download failed: ${res.statusCode} ${res.body}');
          return null;
        }

        final body = json.decode(res.body) as Map<String, dynamic>;
        downloadUrl = body['link'] as String?;
        if (downloadUrl == null) return null;
      } else {
        downloadUrl = item.downloadUrl!;
      }

      print('Downloading subtitle: $downloadUrl');
      final res = await http.get(
        Uri.parse(downloadUrl),
        headers: {'User-Agent': 'HYFLIX v1.0'},
      ).timeout(const Duration(seconds: 15));

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
          if (file.isFile && isSupportedSubtitleFile(file.name)) {
            final rawText = utf8.decode(file.content as List<int>, allowMalformed: true);
            return convertToSrt(rawText, fileName: file.name);
          }
        }
      }
      // GZIP archive
      else if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        final rawText = utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
        return convertToSrt(rawText, fileName: item.fileName);
      }
      // Plain text
      else {
        final rawText = utf8.decode(bytes, allowMalformed: true);
        return convertToSrt(rawText, fileName: item.fileName);
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

  // ─── Local subtitle storage (cross-platform) ───────────────────

  /// Download a season-level ZIP, extract all subtitle files (SRT, ASS, SSA, VTT),
  /// convert them to standard SRT, and save to local storage.
  /// Returns the list of saved SubtitleItems (one per episode subtitle found).
  static Future<List<SubtitleItem>> downloadSeasonSubtitles({
    required SubtitleItem item,
    required String tmdbId,
    required int season,
  }) async {
    if (item.downloadUrl == null) return [];

    try {
      final res = await http.get(
        Uri.parse(item.downloadUrl!),
        headers: {'User-Agent': 'HYFLIX v1.0'},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return [];

      final bytes = res.bodyBytes;
      if (bytes.length < 4) return [];

      final saved = <SubtitleItem>[];

      // ZIP archive
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          if (!file.isFile) continue;
          final name = file.name;
          if (!isSupportedSubtitleFile(name)) continue;

          final rawContent = utf8.decode(file.content as List<int>, allowMalformed: true);
          final srtContent = convertToSrt(rawContent, fileName: name);
          final rawBaseName = name.split('/').last.split('\\').last;
          // Store with .srt extension for consistency
          final baseName = rawBaseName.replaceAll(RegExp(r'\.(ass|ssa|vtt|srt)$', caseSensitive: false), '') + '.srt';
          
          await SubtitleStorage.instance.saveSubtitle(
            tmdbId: tmdbId,
            season: season,
            fileName: baseName,
            content: srtContent,
          );

          final matchType = classifyMatch(baseName, season, null)
              ?? SubtitleMatchType.seasonFallback;

          saved.add(SubtitleItem(
            id: 'local_${baseName.hashCode}',
            fileName: baseName,
            language: item.language,
            source: 'local',
            matchType: matchType,
            localPath: baseName, // Store baseName as localPath reference
          ));
        }
      }
      // GZIP — single subtitle
      else if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        final rawContent = utf8.decode(GZipDecoder().decodeBytes(bytes), allowMalformed: true);
        final srtContent = convertToSrt(rawContent, fileName: item.fileName);
        final baseName = '${item.fileName}.srt';
        
        await SubtitleStorage.instance.saveSubtitle(
          tmdbId: tmdbId,
          season: season,
          fileName: baseName,
          content: srtContent,
        );

        saved.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: item.language,
          source: 'local',
          matchType: SubtitleMatchType.seasonFallback,
          localPath: baseName,
        ));
      }
      // Plain text — single subtitle
      else {
        final rawContent = utf8.decode(bytes, allowMalformed: true);
        final srtContent = convertToSrt(rawContent, fileName: item.fileName);
        final baseName = '${item.fileName}.srt';
        
        await SubtitleStorage.instance.saveSubtitle(
          tmdbId: tmdbId,
          season: season,
          fileName: baseName,
          content: srtContent,
        );

        saved.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: item.language,
          source: 'local',
          matchType: SubtitleMatchType.seasonFallback,
          localPath: baseName,
        ));
      }

      return saved;
    } catch (e) {
      print('Season subtitle download error: $e');
      return [];
    }
  }

  /// Import a single subtitle file content (.srt, .ass, .ssa, .vtt) into local subtitle storage.
  static Future<SubtitleItem?> importLocalSubtitle({
    required String fileName,
    required String content,
    required String tmdbId,
    required int season,
  }) async {
    try {
      final srtContent = convertToSrt(content, fileName: fileName);
      final rawBaseName = fileName.split('/').last.split('\\').last;
      final baseName = rawBaseName.replaceAll(RegExp(r'\.(ass|ssa|vtt|srt)$', caseSensitive: false), '') + '.srt';

      await SubtitleStorage.instance.saveSubtitle(
        tmdbId: tmdbId,
        season: season,
        fileName: baseName,
        content: srtContent,
      );

      final matchType = classifyMatch(baseName, season, null)
          ?? SubtitleMatchType.seasonFallback;

      return SubtitleItem(
        id: 'local_${baseName.hashCode}',
        fileName: baseName,
        language: 'custom',
        source: 'local',
        matchType: matchType,
        localPath: baseName,
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
      final files = await SubtitleStorage.instance.loadSubtitles(
        tmdbId: tmdbId,
        season: season,
      );

      final items = <SubtitleItem>[];
      for (final f in files) {
        final baseName = f['fileName'] as String;
        final localPath = f['localPath'] as String;
        final matchType = classifyMatch(baseName, season, episodeNumber)
            ?? SubtitleMatchType.seasonFallback;

        items.add(SubtitleItem(
          id: 'local_${baseName.hashCode}',
          fileName: baseName,
          language: 'local',
          source: 'local',
          matchType: matchType,
          localPath: localPath,
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
      await SubtitleStorage.instance.deleteSubtitles(
        tmdbId: tmdbId,
        season: season,
      );
    } catch (e) {
      print('Delete local subtitles error: $e');
    }
  }

  /// Read the content of a locally stored subtitle file.
  /// If [episodeNumber] is provided and the file spans multiple episodes,
  /// extracts only the portion for that episode.
  static Future<String?> readLocalSubtitle(String localPath, {int? episodeNumber}) async {
    try {
      final content = await SubtitleStorage.instance.readSubtitle(localPath);
      if (content == null || content.trim().isEmpty) return null;

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

  /// Import a ZIP file containing multiple subtitle files (SRT, ASS, SSA, VTT).
  static Future<List<SubtitleItem>> importLocalSubtitleBatch({
    required List<int> zipBytes,
    required String tmdbId,
    required int season,
  }) async {
    try {
      if (zipBytes.length < 4) return [];
      final saved = <SubtitleItem>[];

      if (zipBytes[0] == 0x50 && zipBytes[1] == 0x4B) {
        final archive = ZipDecoder().decodeBytes(zipBytes);
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final name = entry.name;
          if (!isSupportedSubtitleFile(name)) continue;

          final rawContent = utf8.decode(entry.content as List<int>, allowMalformed: true);
          final srtContent = convertToSrt(rawContent, fileName: name);
          final rawBaseName = entry.name.split('/').last.split('\\').last;
          final baseName = rawBaseName.replaceAll(RegExp(r'\.(ass|ssa|vtt|srt)$', caseSensitive: false), '') + '.srt';
          
          await SubtitleStorage.instance.saveSubtitle(
            tmdbId: tmdbId,
            season: season,
            fileName: baseName,
            content: srtContent,
          );

          final matchType = classifyMatch(baseName, season, null)
              ?? SubtitleMatchType.seasonFallback;

          saved.add(SubtitleItem(
            id: 'local_${baseName.hashCode}',
            fileName: baseName,
            language: 'custom',
            source: 'local',
            matchType: matchType,
            localPath: baseName,
          ));
        }
      }

      return saved;
    } catch (e) {
      print('Batch subtitle import error: $e');
      return [];
    }
  }

  /// Find a local subtitle that matches the current episode number.
  static Future<SubtitleItem?> findMatchingLocalSubtitle({
    required String tmdbId,
    required int season,
    required int episodeNumber,
  }) async {
    final localSubs = await loadLocalSubtitles(
      tmdbId: tmdbId,
      season: season,
      episodeNumber: episodeNumber,
    );
    // Find the first subtitle that is an exact match for this episode
    for (final sub in localSubs) {
      if (sub.matchType == SubtitleMatchType.exactEpisode) {
        return sub;
      }
    }
    return null;
  }
}
