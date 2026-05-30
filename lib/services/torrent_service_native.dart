import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import '../config/app_config.dart';
import '../models/torrent_stream.dart';

export '../models/torrent_stream.dart';

class TorrentService {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  bool _initialized = false;
  int? _activeTorrentId;
  TorrentInfo? _lastTorrentInfo;
  StreamSubscription<Map<int, TorrentInfo>>? _infoSub;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      await LibtorrentFlutter.init(
        fetchTrackers: true,
        pollInterval: const Duration(milliseconds: 400),
      );

      // Apply streaming-optimized configuration
      LibtorrentFlutter.instance.configureSession(const BtConfig(
        cacheSize: 128 * 1024 * 1024,       // 128MB cache (default 64MB)
        readerReadAhead: 95,                  // 95% for read-ahead
        preloadCache: 80,                     // preload 80% of cache on start
        connectionsLimit: 60,                 // 60 concurrent piece requests (default 25)
        torrentDisconnectTimeout: 120,        // keep alive 2 minutes
        forceEncrypt: false,                  // allow both encrypted and plain
        disableTcp: false,                    // keep TCP
        disableUtp: false,                    // keep uTP (avoids ISP throttling)
        disableUpload: false,                 // uploading helps tit-for-tat
        disableDht: false,                    // DHT for peer discovery
        disableUpnp: false,                   // UPnP for port forwarding
        enableIpv6: true,                     // more peers via IPv6
        responsiveMode: true,                 // aggressive streaming mode
      ));

      _initialized = true;
      debugPrint('[TorrentService] Libtorrent initialized with streaming-optimized config');
    } catch (e, st) {
      debugPrint('[TorrentService] Init failed: $e\n$st');
    }
  }

  /// Fetch available streams from Torrentio for a given IMDB ID.
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

      final uri = Uri.parse('$torrentioBaseUrl$path');
      debugPrint('[TorrentService] Fetching streams: $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      debugPrint('[TorrentService] Response: ${res.statusCode}');

      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final streams = body['streams'] as List<dynamic>? ?? [];
      debugPrint('[TorrentService] Raw streams count: ${streams.length}');

      final results = <TorrentStream>[];
      for (final s in streams) {
        final map = s as Map<String, dynamic>;
        final infoHash = map['infoHash'] as String? ?? '';
        if (infoHash.isEmpty) continue;

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
          title: title,
          quality: quality,
          seeders: seeders,
          size: size,
          fileIdx: fileIdx,
          isHDR: isHDR,
          filename: filename,
        ));
      }

      results.sort((a, b) {
        final qA = _qualityRank(a.quality);
        final qB = _qualityRank(b.quality);
        if (qA != qB) return qA.compareTo(qB);
        return b.seeders.compareTo(a.seeders);
      });

      debugPrint('[TorrentService] Parsed ${results.length} streams '
          '(4K: ${results.where((s) => s.quality == "4K").length}, '
          '1080p: ${results.where((s) => s.quality == "1080p").length}, '
          '720p: ${results.where((s) => s.quality == "720p").length})');

      return results;
    } catch (e, st) {
      debugPrint('[TorrentService] fetchStreams error: $e\n$st');
      return [];
    }
  }

  /// Start streaming a torrent. Returns the local HTTP URL for playback.
  Future<String?> startStream(TorrentStream stream) async {
    await _ensureInit();
    if (!_initialized) return null;

    try {
      await stopStream();

      final engine = LibtorrentFlutter.instance;
      final truncatedHash = stream.infoHash.length > 16
          ? '${stream.infoHash.substring(0, 16)}...'
          : stream.infoHash;
      debugPrint('[TorrentService] Adding magnet: hash=$truncatedHash '
          'quality=${stream.quality} fileIdx=${stream.fileIdx}');

      final torrentId = engine.addMagnet(stream.magnetUri, null, true);
      _activeTorrentId = torrentId;
      debugPrint('[TorrentService] Torrent added, id=$torrentId. Waiting for metadata...');

      // Listen to torrentUpdates to cache latest TorrentInfo for stats
      _infoSub?.cancel();
      _infoSub = engine.torrentUpdates.listen((map) {
        final info = map[torrentId];
        if (info != null) _lastTorrentInfo = info;
      });

      // Wait for metadata to be available (timeout after 60s)
      await engine.torrentUpdates
          .where((map) => map[torrentId]?.hasMetadata == true)
          .first
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('Metadata timeout after 60s'),
          );

      debugPrint('[TorrentService] Metadata received for torrent $torrentId');

      if (_activeTorrentId != torrentId) {
        debugPrint('[TorrentService] Torrent was cancelled during metadata wait');
        return null;
      }

      // Focus bandwidth on the target file for multi-file torrents
      final files = engine.getFiles(torrentId);
      if (files.length > 1) {
        final priorities = List<int>.generate(
          files.length,
          (i) => i == stream.fileIdx ? 7 : 0,
        );
        engine.setFilePriorities(torrentId, priorities);
        debugPrint('[TorrentService] Set file priorities: target=${stream.fileIdx} '
            'out of ${files.length} files');
      }

      final streamInfo = engine.startStream(
        torrentId,
        fileIndex: stream.fileIdx,
        maxCacheBytes: 256 * 1024 * 1024, // 256MB stream cache
      );
      final url = streamInfo.url;

      // Preload head+tail bytes for fast playback start
      engine.preloadStream(streamInfo.id, preloadBytes: 16 * 1024 * 1024);

      // Configure per-stream cache for aggressive read-ahead
      engine.setCacheSettings(
        streamInfo.id,
        capacity: 128 * 1024 * 1024, // 128MB
        readAheadPct: 95,
        connectionsLimit: 50,
      );

      debugPrint('[TorrentService] Stream started: $url '
          '(preloaded 16MB, cache 128MB, 50 connections)');
      return url.isNotEmpty ? url : null;
    } catch (e, st) {
      debugPrint('[TorrentService] startStream error: $e\n$st');
      return null;
    }
  }

  /// Stop the active stream and remove the torrent.
  Future<void> stopStream() async {
    if (!_initialized) return;
    try {
      if (_activeTorrentId != null) {
        debugPrint('[TorrentService] Stopping torrent $_activeTorrentId');
        _infoSub?.cancel();
        _infoSub = null;
        _lastTorrentInfo = null;
        final engine = LibtorrentFlutter.instance;
        engine.disposeTorrent(_activeTorrentId!);
        _activeTorrentId = null;
      }
    } catch (e, st) {
      debugPrint('[TorrentService] stopStream error: $e\n$st');
    }
  }

  /// Fetch streams for an episode and return the best one by seeders.
  /// Returns the TorrentStream or null if none found.
  Future<TorrentStream?> fetchBestStream(
    String imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async {
    final streams = await fetchStreams(imdbId, mediaType, season: season, episode: episode);
    if (streams.isEmpty) return null;
    // Prefer 1080p, then highest seeders
    final hd = streams.where((s) => s.quality == '1080p').toList();
    if (hd.isNotEmpty) {
      hd.sort((a, b) => b.seeders.compareTo(a.seeders));
      return hd.first;
    }
    streams.sort((a, b) => b.seeders.compareTo(a.seeders));
    return streams.first;
  }

  /// Get cached torrent stats (download rate, peers, progress, etc.).
  Map<String, dynamic>? getStreamStats() {
    final info = _lastTorrentInfo;
    if (info == null) return null;
    return {
      'downloadRate': info.downloadRate,
      'uploadRate': info.uploadRate,
      'numPeers': info.numPeers,
      'numSeeds': info.numSeeds,
      'progress': info.progress,
      'totalDone': info.totalDone,
      'totalWanted': info.totalWanted,
      'state': info.state.toString(),
      'hasMetadata': info.hasMetadata,
      'isPaused': info.isPaused,
    };
  }

  /// Get the current active torrent ID.
  int? get activeTorrentId => _activeTorrentId;

  /// Get torrent progress updates (0.0 to 1.0).
  Stream<Map<int, TorrentInfo>>? get torrentUpdates {
    if (!_initialized) return null;
    return LibtorrentFlutter.instance.torrentUpdates;
  }

  /// Get stream status updates.
  Stream<Map<int, StreamInfo>>? get streamUpdates {
    if (!_initialized) return null;
    return LibtorrentFlutter.instance.streamUpdates;
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

  Future<void> dispose() async {
    await stopStream();
    if (_initialized) {
      await LibtorrentFlutter.instance.dispose();
      _initialized = false;
      debugPrint('[TorrentService] Disposed');
    }
  }
}
