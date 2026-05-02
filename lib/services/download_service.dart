import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DownloadStatus { pending, downloading, completed, failed, cancelled }

class DownloadItem {
  final String contentId;
  final String contentTitle;
  final int episodeIndex;
  final String episodeName;
  final String m3u8Url;
  final String? filePath;
  final String? thumbnailUrl;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final int etaSeconds;

  const DownloadItem({
    required this.contentId,
    required this.contentTitle,
    required this.episodeIndex,
    required this.episodeName,
    required this.m3u8Url,
    this.filePath,
    this.thumbnailUrl,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = 0.0,
    this.etaSeconds = 0,
  });

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? filePath,
    int? downloadedBytes,
    int? totalBytes,
    double? speed,
    int? etaSeconds,
  }) {
    return DownloadItem(
      contentId: contentId,
      contentTitle: contentTitle,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      m3u8Url: m3u8Url,
      filePath: filePath ?? this.filePath,
      thumbnailUrl: thumbnailUrl,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speed: speed ?? this.speed,
      etaSeconds: etaSeconds ?? this.etaSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'contentId': contentId,
        'contentTitle': contentTitle,
        'episodeIndex': episodeIndex,
        'episodeName': episodeName,
        'm3u8Url': m3u8Url,
        'filePath': filePath,
        'thumbnailUrl': thumbnailUrl,
        'status': status.index,
        'progress': progress,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        contentId: json['contentId'] as String? ?? '',
        contentTitle: json['contentTitle'] as String? ?? '',
        episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 0,
        episodeName: json['episodeName'] as String? ?? '',
        m3u8Url: json['m3u8Url'] as String? ?? '',
        filePath: json['filePath'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        status: DownloadStatus.values[(json['status'] as num?)?.toInt() ?? 0],
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      );
}

class _EncryptionInfo {
  final String method;
  final List<int> keyBytes;
  final List<int> iv;

  const _EncryptionInfo({
    required this.method,
    required this.keyBytes,
    required this.iv,
  });
}

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  static const String _storageKey = 'download_items';

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  SharedPreferences? _prefs;
  final List<DownloadItem> _items = [];
  final Map<String, CancelToken> _cancelTokens = {};
  bool _initialized = false;

  List<DownloadItem> get items => List.unmodifiable(_items);
  List<DownloadItem> get completedDownloads =>
      _items.where((i) => i.status == DownloadStatus.completed).toList();
  List<DownloadItem> get activeDownloads => _items
      .where((i) =>
          i.status == DownloadStatus.downloading ||
          i.status == DownloadStatus.pending)
      .toList();

  Dio _buildDio(String url) {
    final uri = Uri.parse(url);
    final origin = '${uri.scheme}://${uri.authority}';
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'User-Agent': _userAgent,
        'Referer': '$origin/',
        'Accept': '*/*',
      },
      followRedirects: true,
      maxRedirects: 5,
    ));
  }

  Future<void> init() async {
    if (_initialized) return;
    _prefs ??= await SharedPreferences.getInstance();
    _loadItems();
    _initialized = true;
  }

  void _loadItems() {
    final jsonStr = _prefs?.getString(_storageKey);
    if (jsonStr == null) return;
    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      _items.clear();
      _items.addAll(
        list.map((e) => DownloadItem.fromJson(e as Map<String, dynamic>)),
      );
      for (var i = 0; i < _items.length; i++) {
        if (_items[i].status == DownloadStatus.downloading ||
            _items[i].status == DownloadStatus.pending) {
          _items[i] = _items[i].copyWith(status: DownloadStatus.failed);
        }
      }
      _saveToDisk();
    } catch (_) {}
  }

  void _saveToDisk() {
    final jsonList = _items.map((e) => e.toJson()).toList();
    _prefs?.setString(_storageKey, json.encode(jsonList));
  }

  bool isDownloaded(String contentId, int episodeIndex) {
    return _items.any((i) =>
        i.contentId == contentId &&
        i.episodeIndex == episodeIndex &&
        i.status == DownloadStatus.completed &&
        i.filePath != null &&
        File(i.filePath!).existsSync());
  }

  DownloadItem? getDownload(String contentId, int episodeIndex) {
    try {
      return _items.firstWhere(
          (i) => i.contentId == contentId && i.episodeIndex == episodeIndex);
    } catch (_) {
      return null;
    }
  }

  String? getLocalPath(String contentId, int episodeIndex) {
    final item = getDownload(contentId, episodeIndex);
    if (item?.status == DownloadStatus.completed && item?.filePath != null) {
      if (File(item!.filePath!).existsSync()) return item.filePath;
    }
    return null;
  }

  Future<void> startDownload({
    required String contentId,
    required String contentTitle,
    required int episodeIndex,
    required String episodeName,
    required String m3u8Url,
    String? thumbnailUrl,
  }) async {
    if (isDownloaded(contentId, episodeIndex)) return;

    _items.removeWhere(
        (i) => i.contentId == contentId && i.episodeIndex == episodeIndex);

    final item = DownloadItem(
      contentId: contentId,
      contentTitle: contentTitle,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      m3u8Url: m3u8Url,
      thumbnailUrl: thumbnailUrl,
      status: DownloadStatus.downloading,
    );
    _items.insert(0, item);
    _saveToDisk();
    notifyListeners();

    _runDownload(contentId, episodeIndex, m3u8Url);
  }

  /// Resolve an API URL to an actual m3u8 playlist URL.
  /// API URLs are often play pages (HTML) rather than direct m3u8 files.
  Future<String?> _resolveStreamUrl(Dio dio, String apiUrl) async {
    // Already a direct m3u8
    if (apiUrl.endsWith('.m3u8')) {
      debugPrint('[Download] URL is already m3u8: $apiUrl');
      return apiUrl;
    }

    // Try appending /index.m3u8 (hongniuzy2 pattern)
    try {
      final testUrl = '${apiUrl.replaceAll(RegExp(r'/+$'), '')}/index.m3u8';
      debugPrint('[Download] Trying: $testUrl');
      final res = await dio.get<String>(
        testUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final body = res.data ?? '';
      if (body.contains('#EXTM3U')) {
        debugPrint('[Download] Got m3u8 via /index.m3u8');
        return testUrl;
      }
    } catch (_) {}

    // Fetch the HTML page and extract m3u8 URL (ffzy pattern)
    try {
      debugPrint('[Download] Fetching HTML page: $apiUrl');
      final res = await dio.get<String>(apiUrl,
          options: Options(responseType: ResponseType.plain));
      final html = res.data ?? '';

      // Look for m3u8 URL in script tags (e.g. url = "/path/index.m3u8?sign=...")
      final match = RegExp(r'''(?:url|src|file)\s*[:=]\s*['"]([^'"]*\.m3u8[^'"]*)['"]''')
          .firstMatch(html);
      if (match != null) {
        var m3u8Path = match.group(1)!;
        if (m3u8Path.startsWith('/')) {
          final uri = Uri.parse(apiUrl);
          m3u8Path = '${uri.scheme}://${uri.authority}$m3u8Path';
        } else if (!m3u8Path.startsWith('http')) {
          final base =
              apiUrl.substring(0, apiUrl.lastIndexOf('/') + 1);
          m3u8Path = '$base$m3u8Path';
        }
        debugPrint('[Download] Extracted m3u8 from HTML: $m3u8Path');
        return m3u8Path;
      }

      // Look for any .m3u8 URL in the page
      final anyM3u8 = RegExp('https?://[^"<>\\s]+\\.m3u8[^"<>\\s]*')
          .firstMatch(html);
      if (anyM3u8 != null) {
        debugPrint('[Download] Found m3u8 URL in page: ${anyM3u8.group(0)}');
        return anyM3u8.group(0);
      }
    } catch (e) {
      debugPrint('[Download] HTML fetch failed: $e');
    }

    debugPrint('[Download] ERROR: Could not resolve stream URL');
    return null;
  }

  Future<void> _runDownload(
      String contentId, int episodeIndex, String apiUrl) async {
    final key = '${contentId}_$episodeIndex';
    final cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;

    try {
      final dio = _buildDio(apiUrl);

      // 1. Resolve the actual m3u8 URL from the API URL
      final m3u8Url = await _resolveStreamUrl(dio, apiUrl);
      if (m3u8Url == null) {
        debugPrint('[Download] ERROR: Could not resolve stream URL from: $apiUrl');
        _updateItem(contentId, episodeIndex,
            status: DownloadStatus.failed);
        return;
      }

      // 2. Fetch the m3u8 playlist
      debugPrint('[Download] Fetching playlist: $m3u8Url');
      final playlistRes = await dio.get<String>(
        m3u8Url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );

      var resolvedUrl = m3u8Url;
      if (playlistRes.redirects.isNotEmpty) {
        resolvedUrl = playlistRes.redirects.last.location.toString();
      }

      var playlistBody = playlistRes.data ?? '';
      debugPrint('[Download] Playlist: ${playlistBody.length} chars');

      if (playlistBody.isEmpty || !playlistBody.contains('#EXTM3U')) {
        debugPrint('[Download] ERROR: Invalid m3u8 response');
        _updateItem(contentId, episodeIndex,
            status: DownloadStatus.failed);
        return;
      }

      // 3. If master playlist, follow the first variant
      if (playlistBody.contains('#EXT-X-STREAM-INF')) {
        debugPrint('[Download] Master playlist, finding variant');
        final variantUrl = _resolveUrl(resolvedUrl, _extractFirstVariantLine(playlistBody));
        if (variantUrl != null) {
          debugPrint('[Download] Fetching variant: $variantUrl');
          final variantRes = await dio.get<String>(
            variantUrl,
            cancelToken: cancelToken,
            options: Options(responseType: ResponseType.plain),
          );
          if (variantRes.redirects.isNotEmpty) {
            resolvedUrl = variantRes.redirects.last.location.toString();
          } else {
            resolvedUrl = variantUrl;
          }
          playlistBody = variantRes.data ?? '';
          debugPrint('[Download] Variant: ${playlistBody.length} chars');
        }
      }

      // 4. Parse encryption info
      final encInfo = await _parseEncryption(dio, resolvedUrl, playlistBody, cancelToken);
      if (encInfo != null) {
        debugPrint('[Download] Encryption: ${encInfo.method}, key=${encInfo.keyBytes.length}B');
      }

      // 5. Parse segment URLs
      final segmentUrls = _parseSegmentUrls(resolvedUrl, playlistBody);
      debugPrint('[Download] Found ${segmentUrls.length} segments');

      if (segmentUrls.isEmpty) {
        debugPrint('[Download] ERROR: No segments found');
        _updateItem(contentId, episodeIndex,
            status: DownloadStatus.failed);
        return;
      }

      // 6. Prepare output file
      final dir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${dir.path}/downloads');
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }

      final filePath = '${downloadDir.path}/${contentId}_$episodeIndex.ts';
      final outputFile = File(filePath);
      final sink = outputFile.openSync(mode: FileMode.write);

      final totalSegments = segmentUrls.length;
      int downloadedBytes = 0;
      int completedSegments = 0;
      int failedSegments = 0;
      final stopwatch = Stopwatch()..start();

      // 7. Download (and decrypt) segments
      for (final segUrl in segmentUrls) {
        if (cancelToken.isCancelled) {
          await sink.close();
          return;
        }

        try {
          final segRes = await dio.get<List<int>>(
            segUrl,
            cancelToken: cancelToken,
            options: Options(responseType: ResponseType.bytes),
          );
          var data = segRes.data;
          if (data != null && data.isNotEmpty) {
            // Decrypt if encrypted
            if (encInfo != null && encInfo.method == 'AES-128') {
              data = _decryptAes128(data, encInfo.keyBytes, encInfo.iv);
            }
            sink.writeFromSync(data);
            downloadedBytes += data.length;
          }
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) {
            await sink.close();
            return;
          }
          failedSegments++;
          if (failedSegments <= 3) {
            debugPrint('[Download] Segment failed: $segUrl');
            debugPrint('[Download] Error: $e');
          }
        }

        completedSegments++;
        final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
        final progress = completedSegments / totalSegments;
        final speed = elapsed > 0 ? downloadedBytes / elapsed : 0.0;
        final remainingBytes =
            (downloadedBytes / progress * (1 - progress)).round();
        final etaSeconds = speed > 0 ? (remainingBytes / speed).round() : 0;

        _updateItem(
          contentId,
          episodeIndex,
          progress: progress,
          downloadedBytes: downloadedBytes,
          totalBytes: (downloadedBytes / progress).round(),
          speed: speed,
          etaSeconds: etaSeconds,
        );
      }

      await sink.close();

      debugPrint('[Download] Done: $completedSegments segs, '
          '$failedSegments failed, $downloadedBytes bytes');

      if (failedSegments > totalSegments / 2) {
        debugPrint('[Download] ERROR: Too many failed segments');
        _updateItem(contentId, episodeIndex,
            status: DownloadStatus.failed);
        return;
      }

      if (downloadedBytes == 0) {
        debugPrint('[Download] ERROR: Zero bytes downloaded');
        _updateItem(contentId, episodeIndex,
            status: DownloadStatus.failed);
        return;
      }

      _updateItem(
        contentId,
        episodeIndex,
        status: DownloadStatus.completed,
        progress: 1.0,
        filePath: filePath,
        speed: 0,
        etaSeconds: 0,
      );
      debugPrint('[Download] SUCCESS: $filePath');
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) return;
      debugPrint('[Download] FATAL ERROR: $e');
      _updateItem(contentId, episodeIndex,
          status: DownloadStatus.failed);
    } finally {
      _cancelTokens.remove(key);
    }
  }

  void _updateItem(
    String contentId,
    int episodeIndex, {
    DownloadStatus? status,
    double? progress,
    String? filePath,
    int? downloadedBytes,
    int? totalBytes,
    double? speed,
    int? etaSeconds,
  }) {
    final idx = _items.indexWhere(
        (i) => i.contentId == contentId && i.episodeIndex == episodeIndex);
    if (idx == -1) return;

    _items[idx] = _items[idx].copyWith(
      status: status,
      progress: progress,
      filePath: filePath,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speed: speed,
      etaSeconds: etaSeconds,
    );
    _saveToDisk();
    notifyListeners();
  }

  Future<void> cancelDownload(String contentId, int episodeIndex) async {
    final key = '${contentId}_$episodeIndex';
    _cancelTokens[key]?.cancel('User cancelled');

    _items.removeWhere(
        (i) => i.contentId == contentId && i.episodeIndex == episodeIndex);
    _saveToDisk();
    notifyListeners();
  }

  Future<void> deleteDownload(String contentId, int episodeIndex) async {
    final key = '${contentId}_$episodeIndex';
    _cancelTokens[key]?.cancel('User deleted');

    final item = getDownload(contentId, episodeIndex);
    if (item?.filePath != null) {
      try {
        final file = File(item!.filePath!);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _items.removeWhere(
        (i) => i.contentId == contentId && i.episodeIndex == episodeIndex);
    _saveToDisk();
    notifyListeners();
  }

  Future<void> retryDownload({
    required String contentId,
    required String contentTitle,
    required int episodeIndex,
    required String episodeName,
    required String m3u8Url,
    String? thumbnailUrl,
  }) async {
    await deleteDownload(contentId, episodeIndex);
    await startDownload(
      contentId: contentId,
      contentTitle: contentTitle,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      m3u8Url: m3u8Url,
      thumbnailUrl: thumbnailUrl,
    );
  }

  Future<int> getDownloadSize(String contentId, int episodeIndex) async {
    final item = getDownload(contentId, episodeIndex);
    if (item?.filePath == null) return 0;
    try {
      final file = File(item!.filePath!);
      if (file.existsSync()) return await file.length();
    } catch (_) {}
    return 0;
  }
}

// --- URL resolution helpers ---

/// Resolve a potentially relative URL against a base URL.
/// Handles: full URLs, host-absolute paths (/path/...), relative paths.
String? _resolveUrl(String baseUrl, String? relativeUrl) {
  if (relativeUrl == null) return null;
  if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
    return relativeUrl;
  }
  final baseUri = Uri.parse(baseUrl);
  if (relativeUrl.startsWith('/')) {
    // Host-absolute: prepend scheme + authority
    return '${baseUri.scheme}://${baseUri.authority}$relativeUrl';
  }
  // Relative: prepend base directory
  final basePath =
      baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
  return '${baseUri.scheme}://${baseUri.authority}$basePath$relativeUrl';
}

/// Extract the first variant URL line from a master playlist.
String? _extractFirstVariantLine(String playlist) {
  final lines = playlist.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('#EXT-X-STREAM-INF')) {
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        return next;
      }
    }
  }
  return null;
}

/// Parse segment URLs from a media playlist.
List<String> _parseSegmentUrls(String baseUrl, String playlist) {
  final segments = <String>[];
  final lines = playlist.split('\n');

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final resolved = _resolveUrl(baseUrl, trimmed);
    if (resolved != null) segments.add(resolved);
  }

  return segments;
}

/// Parse encryption info from a variant playlist.
/// Returns null if no encryption or method is NONE.
Future<_EncryptionInfo?> _parseEncryption(
  Dio dio,
  String variantUrl,
  String playlist,
  CancelToken cancelToken,
) async {
  final lines = playlist.split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#EXT-X-KEY')) continue;

    final methodMatch = RegExp(r'METHOD=([^,\s]+)').firstMatch(trimmed);
    if (methodMatch == null) continue;
    final method = methodMatch.group(1)!;
    if (method == 'NONE') return null;

    final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
    if (uriMatch == null) continue;
    final keyUri = _resolveUrl(variantUrl, uriMatch.group(1)!);

    final ivMatch = RegExp(r'IV=([^,\s]+)').firstMatch(trimmed);
    List<int> iv;
    if (ivMatch != null) {
      final ivHex = ivMatch.group(1)!.replaceFirst('0x', '');
      iv = _hexToBytes(ivHex);
    } else {
      // Default IV: sequence number (0 for our case since we concat all segments)
      iv = List.filled(16, 0);
    }

    // Fetch the encryption key
    debugPrint('[Download] Fetching encryption key: $keyUri');
    final keyRes = await dio.get<List<int>>(
      keyUri!,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes),
    );
    final keyBytes = keyRes.data;
    if (keyBytes == null || keyBytes.isEmpty) {
      debugPrint('[Download] WARNING: Empty encryption key');
      return null;
    }

    return _EncryptionInfo(method: method, keyBytes: keyBytes, iv: iv);
  }
  return null;
}

/// Decrypt AES-128-CBC encrypted data.
List<int> _decryptAes128(List<int> encrypted, List<int> key, List<int> iv) {
  final encrypter = encrypt.Encrypter(
    encrypt.AES(
      encrypt.Key(Uint8List.fromList(key)),
      mode: encrypt.AESMode.cbc,
      padding: 'PKCS7',
    ),
  );
  final decrypted = encrypter.decryptBytes(
    encrypt.Encrypted(Uint8List.fromList(encrypted)),
    iv: encrypt.IV(Uint8List.fromList(iv)),
  );
  return decrypted;
}

List<int> _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}
