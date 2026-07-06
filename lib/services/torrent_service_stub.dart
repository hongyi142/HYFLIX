import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/torrent_stream.dart';

export '../models/torrent_stream.dart';

/// Web-compatible TorrentService that uses HTTP direct play streams from TorBox debrid.
/// Disables native C++ libtorrent components which are unavailable on Web.
class TorrentService {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  /// Resolves the effective Torrentio URL based on config credentials.
  String getEffectiveTorrentioUrl() {
    if (customTorrentioUrl.isNotEmpty) {
      String url = customTorrentioUrl;
      if (url.startsWith('stremio://')) {
        url = 'https://${url.substring(10)}';
      }
      if (url.endsWith('/manifest.json')) {
        url = url.substring(0, url.length - 14);
      }
      while (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      return url;
    }
    
    if (torboxApiKey.isNotEmpty && torboxApiKey != 'YOUR_TORBOX_API_KEY') {
      return '$torrentioBaseUrl/providers=yts,eztv,rarbg,1337x,thepiratebay,kickasstorrents,torrentgalaxy|torbox=$torboxApiKey';
    }
    
    return torrentioBaseUrl;
  }

  /// Fetch available debrid streams from Torrentio on the web.
  /// Standard P2P torrents are filtered out because the web platform cannot play them.
  Future<List<TorrentStream>> fetchStreams(
    String imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    try {
      String path;
      if (mediaType == 'tv' && season != null && episode != null) {
        path = '/stream/series/$imdbId:$season:$episode.json';
      } else {
        path = '/stream/movie/$imdbId.json';
      }

      final baseUrl = getEffectiveTorrentioUrl();
      final uri = Uri.parse('$baseUrl$path');
      debugPrint('[TorrentService:Web] Querying: $uri');
      
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final streams = body['streams'] as List<dynamic>? ?? [];

      final results = <TorrentStream>[];
      for (final s in streams) {
        final map = s as Map<String, dynamic>;
        final url = map['url'] as String? ?? '';
        
        // Web ONLY supports debrid direct play links (where url is present)
        if (url.isEmpty) continue;

        String infoHash = map['infoHash'] as String? ?? '';
        if (infoHash.isEmpty) {
          infoHash = url.hashCode.toRadixString(16).padLeft(40, '0');
        }

        final title = map['title'] as String? ?? '';
        final name = map['name'] as String? ?? '';
        final filename = (map['behaviorHints'] as Map<String, dynamic>?)?['filename'] as String? ?? '';
        final fileIdx = map['fileIdx'] as int? ?? 0;

        final fullTitle = '$title $name $filename';
        final quality = _extractQuality(fullTitle);
        final isHDR = fullTitle.toLowerCase().contains('hdr') ||
            fullTitle.toLowerCase().contains('dolby vision') ||
            fullTitle.toLowerCase().contains('dv');
        final seeders = _extractSeeders(title);
        final size = _extractSize(title);

        results.add(TorrentStream(
          infoHash: infoHash,
          url: url,
          title: title,
          quality: quality,
          seeders: seeders,
          size: size,
          fileIdx: fileIdx,
          isHDR: isHDR,
          filename: filename,
          source: _addonName(baseUrl),
        ));
      }

      results.sort((a, b) {
        final qA = _qualityRank(a.quality);
        final qB = _qualityRank(b.quality);
        if (qA != qB) return qA.compareTo(qB);

        // Prioritize web-compatible formats (H.264 MP4/WebM) over unsupported browser formats (MKV/HEVC/10bit)
        final titleA = '${a.title} ${a.filename}'.toLowerCase();
        final titleB = '${b.title} ${b.filename}'.toLowerCase();
        
        final isCompA = (titleA.contains('.mp4') || titleA.contains('.m4v') || titleA.contains('.webm')) &&
                        !(titleA.contains('.mkv') || titleA.contains('.avi') || titleA.contains('.ts')) &&
                        !(titleA.contains('x265') || titleA.contains('hevc') || titleA.contains('h.265') || titleA.contains('h265') || titleA.contains('10bit'))
            ? 1 : 0;
        final isCompB = (titleB.contains('.mp4') || titleB.contains('.m4v') || titleB.contains('.webm')) &&
                        !(titleB.contains('.mkv') || titleB.contains('.avi') || titleB.contains('.ts')) &&
                        !(titleB.contains('x265') || titleB.contains('hevc') || titleB.contains('h.265') || titleB.contains('h265') || titleB.contains('10bit'))
            ? 1 : 0;
            
        if (isCompA != isCompB) {
          return isCompB.compareTo(isCompA); // Compatible (1) comes before incompatible (0)
        }

        return b.seeders.compareTo(a.seeders);
      });

      debugPrint('[TorrentService:Web] Found ${results.length} debrid streams');
      return results;
    } catch (e, st) {
      debugPrint('[TorrentService:Web] fetchStreams error: $e\n$st');
      return [];
    }
  }

  Future<(String, int)?> startStream(TorrentStream stream) async {
    if (stream.url != null && stream.url!.isNotEmpty) {
      return (stream.url!, 0);
    }
    return null;
  }

  Future<bool> waitForBuffer(
    int streamId, {
    double targetBufferSeconds = 10.0,
    Duration timeout = const Duration(seconds: 20),
  }) async => true;

  Stream<Map<int, dynamic>>? get streamUpdates => null;

  Future<void> stopStream() async {}

  Future<TorrentStream?> fetchBestStream(
    String imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    final streams = await fetchStreams(imdbId, mediaType, season: season, episode: episode);
    if (streams.isEmpty) return null;
    final hd = streams.where((s) => s.quality == '1080p').toList();
    if (hd.isNotEmpty) {
      hd.sort((a, b) => b.seeders.compareTo(a.seeders));
      return hd.first;
    }
    streams.sort((a, b) => b.seeders.compareTo(a.seeders));
    return streams.first;
  }

  Map<String, dynamic>? getStreamStats() => null;

  int? get activeTorrentId => null;

  Future<void> dispose() async {}

  static String _addonName(String baseUrl) {
    if (baseUrl.contains('torrentio')) {
      if (baseUrl.contains('torbox')) return 'Torrentio (TorBox)';
      return 'Torrentio';
    }
    return baseUrl;
  }

  static String _extractQuality(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd')) return '4K';
    if (lower.contains('1080p')) return '1080p';
    if (lower.contains('720p')) return '720p';
    if (lower.contains('480p')) return '480p';
    return 'Unknown';
  }

  static int _qualityRank(String quality) {
    switch (quality) {
      case '4K': return 0;
      case '1080p': return 1;
      case '720p': return 2;
      case '480p': return 3;
      default: return 4;
    }
  }

  static int _extractSeeders(String title) {
    final match = RegExp(r'👤\s*(\d+)').firstMatch(title);
    if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    final match2 = RegExp(r'[Ss]eeders?:?\s*(\d+)').firstMatch(title);
    if (match2 != null) return int.tryParse(match2.group(1)!) ?? 0;
    return 0;
  }

  static String _extractSize(String title) {
    final match = RegExp(r'💾\s*([\d.]+\s*[KMGT]B)').firstMatch(title);
    if (match != null) return match.group(1)!;
    final match2 = RegExp(r'([\d.]+\s*[KMGT]B)').firstMatch(title);
    if (match2 != null) return match2.group(1)!;
    return '';
  }
}
