import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:libtorrent_flutter/libtorrent_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/torrent_stream.dart';

export '../models/torrent_stream.dart';

class TorrentService {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  bool _initialized = false;
  int? _activeTorrentId;
  int? _activeStreamId;
  TorrentInfo? _lastTorrentInfo;
  StreamSubscription<Map<int, TorrentInfo>>? _infoSub;
  String? _torrentCacheDir;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    try {
      await LibtorrentFlutter.init(
        fetchTrackers: true,
        pollInterval: const Duration(milliseconds: 200),
      );

      // Apply streaming-optimized configuration
      LibtorrentFlutter.instance.configureSession(const BtConfig(
        cacheSize: 256 * 1024 * 1024,       // 256MB cache for smooth playback
        readerReadAhead: 95,                  // (stored but unused by serve_range)
        preloadCache: 40,                     // preload 40% of cache on start
        connectionsLimit: 80,                 // 80 concurrent piece requests (default 25)
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

  /// Ensure the persistent torrent cache directory exists.
  Future<String> _ensureCacheDir() async {
    if (_torrentCacheDir != null) return _torrentCacheDir!;
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}${Platform.pathSeparator}torrent_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _torrentCacheDir = cacheDir.path;
    return _torrentCacheDir!;
  }

  /// Get a per-torrent save path for resume data caching.
  Future<String> _savePathForTorrent(String infoHash) async {
    final base = await _ensureCacheDir();
    final dir = Directory('$base${Platform.pathSeparator}$infoHash');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// All Stremio addon base URLs to query for streams.
  static const List<String> _addonBaseUrls = [
    torrentioBaseUrl,
    thepiratebayBaseUrl,
    meteorBaseUrl,
  ];

  /// Fetch available streams from all Stremio addons for a given IMDB ID.
  /// Queries multiple addons in parallel and deduplicates by infoHash.
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

      // Query all addons in parallel
      final futures = _addonBaseUrls.map((baseUrl) =>
          _fetchFromAddon(baseUrl, path));
      final allResults = await Future.wait(futures);

      // Merge and deduplicate by infoHash, keeping the entry with more seeders
      final byHash = <String, TorrentStream>{};
      for (final streams in allResults) {
        for (final stream in streams) {
          final existing = byHash[stream.infoHash];
          if (existing == null || stream.seeders > existing.seeders) {
            byHash[stream.infoHash] = stream;
          }
        }
      }

      final results = byHash.values.toList();
      results.sort((a, b) {
        final qA = _qualityRank(a.quality);
        final qB = _qualityRank(b.quality);
        if (qA != qB) return qA.compareTo(qB);
        return b.seeders.compareTo(a.seeders);
      });

      debugPrint('[TorrentService] Merged ${results.length} unique streams '
          '(4K: ${results.where((s) => s.quality == "4K").length}, '
          '1080p: ${results.where((s) => s.quality == "1080p").length}, '
          '720p: ${results.where((s) => s.quality == "720p").length})');

      return results;
    } catch (e, st) {
      debugPrint('[TorrentService] fetchStreams error: $e\n$st');
      return [];
    }
  }

  /// Fetch streams from a single Stremio addon.
  Future<List<TorrentStream>> _fetchFromAddon(
      String baseUrl, String path) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return [];

      final body = json.decode(res.body) as Map<String, dynamic>;
      final streams = body['streams'] as List<dynamic>? ?? [];

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
          source: _addonName(baseUrl),
        ));
      }

      debugPrint('[TorrentService] ${_addonName(baseUrl)}: ${results.length} streams');
      return results;
    } catch (e) {
      debugPrint('[TorrentService] ${_addonName(baseUrl)} failed: $e');
      return [];
    }
  }

  static String _addonName(String baseUrl) {
    if (baseUrl.contains('torrentio')) return 'Torrentio';
    if (baseUrl.contains('piratebay')) return 'TPB+';
    if (baseUrl.contains('meteor')) return 'Meteor';
    return baseUrl;
  }

  /// Start streaming a torrent. Returns the local HTTP URL and stream ID.
  Future<(String url, int streamId)?> startStream(TorrentStream stream) async {
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

      // Use persistent save path so libtorrent can load resume data on repeat plays
      final savePath = await _savePathForTorrent(stream.infoHash);
      final torrentId = engine.addMagnet(stream.magnetUri, savePath, true);
      _activeTorrentId = torrentId;
      debugPrint('[TorrentService] Torrent added, id=$torrentId. Waiting for metadata...');

      // Listen to torrentUpdates to cache latest TorrentInfo for stats
      _infoSub?.cancel();
      _infoSub = engine.torrentUpdates.listen((map) {
        final info = map[torrentId];
        if (info != null) _lastTorrentInfo = info;
      });

      // Wait for metadata to be available (timeout after 60s)
      // With resume data, this completes almost instantly (~200ms)
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

      // IMPORTANT: Do NOT call setFilePriorities() before startStream().
      // prioritize_files() is ASYNC — if it completes after startStream() sets
      // per-piece priorities, it resets ALL piece priorities back to file-level
      // defaults, undoing the sequential streaming setup and causing the player
      // to wait for the entire file to download.
      // startStream() handles piece prioritization internally (head/tail priority,
      // sequential serving via serve_range).

      final streamInfo = engine.startStream(
        torrentId,
        fileIndex: stream.fileIdx,
        maxCacheBytes: 256 * 1024 * 1024, // 256MB piece cache
      );
      _activeStreamId = streamInfo.id;

      // Tune per-stream cache for aggressive preloading
      engine.setCacheSettings(
        streamInfo.id,
        capacity: 256 * 1024 * 1024,
        readAheadPct: 90,
        connectionsLimit: 120,
      );

      // Preload 32MB head+tail (doubled from 16MB for 4K streams)
      engine.preloadStream(streamInfo.id, preloadBytes: 32 * 1024 * 1024);

      final url = streamInfo.url;
      debugPrint('[TorrentService] Stream started: $url (streamId=${streamInfo.id})');
      return url.isNotEmpty ? (url, streamInfo.id) : null;
    } catch (e, st) {
      debugPrint('[TorrentService] startStream error: $e\n$st');
      return null;
    }
  }

  /// Wait until the stream has buffered enough data for smooth playback.
  /// Returns true if the target buffer was reached, false on timeout.
  Future<bool> waitForBuffer(
    int streamId, {
    double targetBufferSeconds = 10.0,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final engine = LibtorrentFlutter.instance;

    // Fast-path: check if buffer is already sufficient
    final current = engine.getStreamInfo(streamId);
    if (current != null && current.bufferSeconds >= targetBufferSeconds) {
      debugPrint('[TorrentService] Buffer already at '
          '${current.bufferSeconds.toStringAsFixed(1)}s, skipping wait');
      return true;
    }

    final completer = Completer<bool>();
    StreamSubscription<Map<int, StreamInfo>>? sub;
    Timer? timeoutTimer;

    sub = engine.streamUpdates.listen((streams) {
      final info = streams[streamId];
      if (info == null) return;

      debugPrint('[TorrentService] Buffer: ${info.bufferSeconds.toStringAsFixed(1)}s '
          '(${info.bufferPieces}/${info.readaheadWindow} pieces, '
          '${info.downloadRate ~/ 1024} KB/s)');

      if (info.bufferSeconds >= targetBufferSeconds) {
        timeoutTimer?.cancel();
        sub?.cancel();
        if (!completer.isCompleted) completer.complete(true);
      }
    });

    timeoutTimer = Timer(timeout, () {
      sub?.cancel();
      if (!completer.isCompleted) {
        debugPrint('[TorrentService] Buffer timeout after ${timeout.inSeconds}s, starting anyway');
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Stop the active stream and remove the torrent (preserves resume data).
  Future<void> stopStream() async {
    if (!_initialized) return;
    try {
      if (_activeTorrentId != null) {
        debugPrint('[TorrentService] Stopping torrent $_activeTorrentId');
        _infoSub?.cancel();
        _infoSub = null;
        _lastTorrentInfo = null;
        final engine = LibtorrentFlutter.instance;
        // Stop the HTTP streaming server first
        if (_activeStreamId != null) {
          engine.stopStream(_activeStreamId!);
          _activeStreamId = null;
        }
        // Remove torrent but keep files + resume data for faster replay
        engine.removeTorrent(_activeTorrentId!, deleteFiles: false);
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
    if (_initialized) {
      // Final cleanup: stop stream and delete all cached data
      if (_activeTorrentId != null) {
        _infoSub?.cancel();
        _infoSub = null;
        _lastTorrentInfo = null;
        final engine = LibtorrentFlutter.instance;
        if (_activeStreamId != null) {
          engine.stopStream(_activeStreamId!);
          _activeStreamId = null;
        }
        engine.removeTorrent(_activeTorrentId!, deleteFiles: true);
        _activeTorrentId = null;
      }
      await LibtorrentFlutter.instance.dispose();
      _initialized = false;
      debugPrint('[TorrentService] Disposed');
    }
  }
}
