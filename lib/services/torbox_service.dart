import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/torrent_stream.dart';

/// Service to resolve raw torrent streams (infoHash/magnet) into direct HTTPS
/// streaming URLs via TorBox REST API.
class TorBoxService {
  static final TorBoxService _instance = TorBoxService._internal();
  factory TorBoxService() => _instance;
  TorBoxService._internal();

  static const String _apiBase = 'https://api.torbox.app/v1/api';

  /// Check whether a valid TorBox API key is configured.
  bool get isConfigured =>
      torboxApiKey.isNotEmpty && torboxApiKey != 'YOUR_TORBOX_API_KEY';

  /// Check which torrent hashes are cached in TorBox.
  /// Returns a Set of cached infoHashes (lowercase).
  Future<Set<String>> checkCachedHashes(List<String> hashes) async {
    if (!isConfigured || hashes.isEmpty) return {};

    final cleanHashes = hashes
        .where((h) => h.isNotEmpty)
        .map((h) => h.toLowerCase())
        .toSet()
        .toList();
    if (cleanHashes.isEmpty) return {};

    final cachedSet = <String>{};
    final batchFutures = <Future<Set<String>>>[];

    for (int i = 0; i < cleanHashes.length; i += 20) {
      final end = (i + 20 < cleanHashes.length) ? i + 20 : cleanHashes.length;
      final batch = cleanHashes.sublist(i, end);
      batchFutures.add(_checkCachedBatch(batch));
    }

    try {
      final results = await Future.wait(batchFutures);
      for (final res in results) {
        cachedSet.addAll(res);
      }
    } catch (e) {
      debugPrint('[TorBoxService] checkCachedHashes error: $e');
    }

    return cachedSet;
  }

  Future<Set<String>> _checkCachedBatch(List<String> batch) async {
    final cachedSet = <String>{};
    try {
      final queryHash = batch.join(',');
      final url = Uri.parse('$_apiBase/torrents/checkcached?hash=$queryHash');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer $torboxApiKey',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            data.forEach((hash, value) {
              if (value != null && value != false) {
                cachedSet.add(hash.toLowerCase());
              }
            });
          } else if (data is List) {
            for (final item in data) {
              if (item is Map && item['hash'] != null) {
                cachedSet.add(item['hash'].toString().toLowerCase());
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[TorBoxService] _checkCachedBatch failed: $e');
    }
    return cachedSet;
  }

  /// Resolve a [TorrentStream] (with magnetUri/infoHash) into a direct HTTPS streaming URL.
  /// Returns the resolved direct stream URL, or null if resolution fails.
  Future<String?> resolveStream(TorrentStream stream) async {
    if (!isConfigured) {
      debugPrint('[TorBoxService] TorBox API key is not configured.');
      return null;
    }

    if (stream.url != null && stream.url!.isNotEmpty) {
      return stream.url;
    }

    final infoHash = stream.infoHash;
    if (infoHash.isEmpty) {
      debugPrint('[TorBoxService] Stream has no infoHash or URL.');
      return null;
    }

    final magnetUri = stream.magnetUri;
    debugPrint('[TorBoxService] Resolving stream via TorBox API: $infoHash');

    try {
      // Step 1: Add torrent to TorBox account via createtorrent
      final torrentId = await _addTorrent(magnetUri);
      if (torrentId == null) {
        debugPrint('[TorBoxService] Failed to add torrent to TorBox.');
        return null;
      }

      // Step 2: Retrieve torrent file details (polled if metadata is downloading)
      final fileId = await _getBestFileId(torrentId, preferredFileIdx: stream.fileIdx);
      final targetFileId = fileId ?? stream.fileIdx;

      // Step 3: Request direct download/stream link
      final directUrl = await _requestDownloadLink(torrentId, targetFileId);
      if (directUrl != null && directUrl.isNotEmpty) {
        debugPrint('[TorBoxService] Resolved direct TorBox stream URL: $directUrl');
        return directUrl;
      }

      // Guaranteed fallback: Return redirect permalink URL so TorBox handles streaming over HTTPS
      final permalink = '$_apiBase/torrents/requestdl?token=$torboxApiKey&torrent_id=$torrentId&file_id=$targetFileId&redirect=true';
      debugPrint('[TorBoxService] Using TorBox permalink redirect URL: $permalink');
      return permalink;
    } catch (e, st) {
      debugPrint('[TorBoxService] Exception during stream resolution: $e\n$st');
      return null;
    }
  }

  /// Send magnet link to POST /v1/api/torrents/createtorrent
  Future<int?> _addTorrent(String magnetUri) async {
    final url = Uri.parse('$_apiBase/torrents/createtorrent');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $torboxApiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'magnet': magnetUri},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 && response.statusCode != 201) {
      debugPrint('[TorBoxService] createtorrent HTTP error ${response.statusCode}: ${response.body}');
      return null;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    if (body['success'] == true && body['data'] != null) {
      final data = body['data'] as Map<String, dynamic>;
      final id = data['torrent_id'] ?? data['id'];
      if (id != null) {
        return (id is int) ? id : int.tryParse(id.toString());
      }
    }

    debugPrint('[TorBoxService] createtorrent response missing torrent_id: ${response.body}');
    return null;
  }

  /// Poll GET /v1/api/torrents/mylist?id={torrentId} until files list is available,
  /// then find the best video file index.
  Future<int?> _getBestFileId(int torrentId, {int preferredFileIdx = 0}) async {
    final url = Uri.parse('$_apiBase/torrents/mylist?id=$torrentId');
    
    // Poll up to 10 times (total ~15s) for metadata to fetch if torrent was newly added
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        final res = await http.get(url, headers: {
          'Authorization': 'Bearer $torboxApiKey',
        }).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          if (body['success'] == true && body['data'] != null) {
            final data = body['data'] as Map<String, dynamic>;
            final files = data['files'] as List<dynamic>?;

            if (files != null && files.isNotEmpty) {
              return _selectVideoFileId(files, preferredFileIdx: preferredFileIdx);
            }
          }
        }
      } catch (e) {
        debugPrint('[TorBoxService] Poll mylist attempt $attempt failed: $e');
      }

      await Future.delayed(const Duration(milliseconds: 1500));
    }

    return null;
  }

  /// Select the best video file ID from the torrent's file list.
  int? _selectVideoFileId(List<dynamic> files, {int preferredFileIdx = 0}) {
    final videoExts = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.ts', '.m2ts', '.flv'};

    final fileList = <Map<String, dynamic>>[];
    for (final f in files) {
      if (f is Map<String, dynamic>) {
        fileList.add(f);
      }
    }
    if (fileList.isEmpty) return null;

    // Check if preferredFileIdx matches a video file
    if (preferredFileIdx >= 0 && preferredFileIdx < fileList.length) {
      final preferred = fileList[preferredFileIdx];
      final name = (preferred['name'] as String? ?? '').toLowerCase();
      if (videoExts.any((ext) => name.endsWith(ext))) {
        final fileId = preferred['id'];
        return (fileId is int) ? fileId : int.tryParse(fileId.toString());
      }
    }

    // Filter all video files and pick the largest one
    Map<String, dynamic>? largestVideo;
    int maxSizeBytes = 0;

    for (final file in fileList) {
      final name = (file['name'] as String? ?? '').toLowerCase();
      final size = file['size'] as int? ?? 0;
      final isVideo = videoExts.any((ext) => name.endsWith(ext));

      if (isVideo && size > maxSizeBytes) {
        maxSizeBytes = size;
        largestVideo = file;
      }
    }

    if (largestVideo != null) {
      final fileId = largestVideo['id'];
      return (fileId is int) ? fileId : int.tryParse(fileId.toString());
    }

    // Fallback to first file's ID if no explicit video extension matched
    final firstId = fileList.first['id'];
    return (firstId is int) ? firstId : int.tryParse(firstId.toString());
  }

  /// Request direct streaming URL via GET /v1/api/torrents/requestdl
  Future<String?> _requestDownloadLink(int torrentId, int fileId) async {
    final url = Uri.parse(
        '$_apiBase/torrents/requestdl?token=$torboxApiKey&torrent_id=$torrentId&file_id=$fileId&zip=false');

    final res = await http.get(url, headers: {
      'Authorization': 'Bearer $torboxApiKey',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final body = json.decode(res.body) as Map<String, dynamic>;
      if (body['success'] == true && body['data'] != null) {
        return body['data'].toString();
      }
    }

    debugPrint('[TorBoxService] requestdl error ${res.statusCode}: ${res.body}');
    return null;
  }
}
