import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class FirestoreService {
  static const String _dbUrl = 'https://hyflix-56557-default-rtdb.asia-southeast1.firebasedatabase.app';

  static String get _usersPath => '$_dbUrl/users/${AuthService.uid}';

  // ── Helpers ──────────────────────────────────────────────────────────

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  // ── User Profile ─────────────────────────────────────────────────────

  static Future<void> createProfile({
    required String email,
    required String displayName,
  }) async {
    await _put('$_usersPath.json', {
      'email': email,
      'displayName': displayName,
      'watchTimeSeconds': 0,
      'favourites': {},
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'photoBase64': '',
    });
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    return await _get('$_usersPath.json');
  }

  // ── Watch History ────────────────────────────────────────────────────

  static Future<void> saveWatchHistory({
    required String contentId,
    required String title,
    required String posterUrl,
    required double progress,
    String originalTitle = '',
    String tmdbId = '',
    int episodeIndex = 0,
    int positionSeconds = 0,
    String m3u8Url = '',
    List<Map<String, dynamic>> episodes = const [],
    int episodeCount = 0,
    int seasonNumber = 1,
  }) async {
    final safeId = contentId.replaceAll(RegExp(r'[.\#\$\[\]]'), '_');
    await _put('$_usersPath/watchHistory/$safeId.json', {
      'title': title,
      'originalTitle': originalTitle,
      'tmdbId': tmdbId,
      'posterUrl': posterUrl,
      'progress': progress,
      'episodeIndex': episodeIndex,
      'positionSeconds': positionSeconds,
      'm3u8Url': m3u8Url,
      'episodes': episodes,
      'episodeCount': episodeCount,
      'seasonNumber': seasonNumber,
      'lastWatched': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getWatchHistory() async {
    final data = await _get('$_usersPath/watchHistory.json');
    if (data == null) return [];

    final items = <Map<String, dynamic>>[];
    for (final entry in data.entries) {
      if (entry.value is Map<String, dynamic>) {
        items.add({'id': entry.key, ...entry.value});
      }
    }

    items.sort((a, b) {
      final aTime = a['lastWatched'] ?? '';
      final bTime = b['lastWatched'] ?? '';
      return bTime.toString().compareTo(aTime.toString());
    });

    return items;
  }

  // ── Profile Updates ──────────────────────────────────────────────────

  static Future<void> updateDisplayName(String displayName) async {
    await _patch('$_usersPath.json', {'displayName': displayName});
  }

  static Future<void> updateEmail(String email) async {
    await _patch('$_usersPath.json', {'email': email});
  }

  static Future<void> updatePhotoBase64(String? base64) async {
    if (base64 != null && base64.isNotEmpty) {
      await _patch('$_usersPath.json', {'photoBase64': base64});
    } else {
      await _patch('$_usersPath.json', {'photoBase64': null});
    }
  }

  // ── Intro Timestamps ───────────────────────────────────────────────

  static Future<void> saveIntroTimestamp({
    required String contentId,
    required int skipDuration,
  }) async {
    final safeId = contentId.replaceAll(RegExp(r'[.\#\$\[\]]'), '_');
    await _patch('$_usersPath/skipIntros/$safeId.json', {
      'skipDuration': skipDuration,
    });
  }

  static Future<Map<String, dynamic>?> getIntroTimestamp(String contentId) async {
    final safeId = contentId.replaceAll(RegExp(r'[.\#\$\[\]]'), '_');
    return await _get('$_usersPath/skipIntros/$safeId.json');
  }

  // ── Watch History Management ────────────────────────────────────────

  static Future<void> clearWatchHistory() async {
    await _put('$_usersPath/watchHistory.json', {});
  }

  // ── Watch Time ───────────────────────────────────────────────────────

  static Future<void> addWatchTime(int seconds) async {
    final profile = await getProfile();
    final current = (profile?['watchTimeSeconds'] as int?) ?? 0;
    await _patch('$_usersPath.json', {
      'watchTimeSeconds': current + seconds,
    });
  }

  static Future<int> getWatchTimeSeconds() async {
    final profile = await getProfile();
    return (profile?['watchTimeSeconds'] as int?) ?? 0;
  }

  // ── Favourites ───────────────────────────────────────────────────────

  static Future<void> toggleFavourite(String contentId) async {
    final profile = await getProfile();
    final favsMap = Map<String, dynamic>.from(profile?['favourites'] ?? {});
    if (favsMap.containsKey(contentId)) {
      favsMap.remove(contentId);
    } else {
      favsMap[contentId] = true;
    }
    await _patch('$_usersPath.json', {
      'favourites': favsMap,
    });
  }

  static Future<bool> isFavourite(String contentId) async {
    final profile = await getProfile();
    final favsMap = Map<String, dynamic>.from(profile?['favourites'] ?? {});
    return favsMap.containsKey(contentId);
  }

  static Future<List<String>> getFavouriteIds() async {
    final profile = await getProfile();
    final favsMap = Map<String, dynamic>.from(profile?['favourites'] ?? {});
    return favsMap.keys.toList();
  }

  // ── Watchlists ───────────────────────────────────────────────────────

  static String _encodeListName(String name) =>
      name.replaceAll(RegExp(r'[.\#\$\[\]/]'), '_');

  /// Save an entire list's items to Firebase (replaces existing).
  static Future<void> saveWatchlist(String listName, List<Map<String, dynamic>> items) async {
    final safeName = _encodeListName(listName);
    final itemsMap = <String, dynamic>{};
    for (final item in items) {
      final title = (item['title'] as String?) ?? '';
      if (title.isEmpty) continue;
      final safeTitle = title.replaceAll(RegExp(r'[.\#\$\[\]/]'), '_');
      itemsMap[safeTitle] = item;
    }
    await _put('$_usersPath/watchlists/$safeName/items.json', itemsMap);
  }

  /// Add a single item to a list in Firebase.
  static Future<void> addToList(String listName, Map<String, dynamic> item) async {
    final safeName = _encodeListName(listName);
    final title = (item['title'] as String?) ?? '';
    if (title.isEmpty) return;
    final safeTitle = title.replaceAll(RegExp(r'[.\#\$\[\]/]'), '_');
    await _put('$_usersPath/watchlists/$safeName/items/$safeTitle.json', item);
  }

  /// Remove a single item from a list in Firebase (by title).
  static Future<void> removeFromList(String listName, String title) async {
    final safeName = _encodeListName(listName);
    final safeTitle = title.replaceAll(RegExp(r'[.\#\$\[\]/]'), '_');
    await _put('$_usersPath/watchlists/$safeName/items/$safeTitle.json', null);
  }

  /// Delete an entire list from Firebase.
  static Future<void> deleteWatchlist(String listName) async {
    final safeName = _encodeListName(listName);
    await _put('$_usersPath/watchlists/$safeName.json', null);
  }

  /// Get all watchlists from Firebase. Returns {listName: [items]}.
  static Future<Map<String, List<Map<String, dynamic>>>> getWatchlists() async {
    final data = await _get('$_usersPath/watchlists.json');
    if (data == null) return {};

    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in data.entries) {
      final listName = entry.key;
      final listData = entry.value;
      if (listData is Map<String, dynamic>) {
        final itemsRaw = listData['items'];
        if (itemsRaw is Map<String, dynamic>) {
          result[listName] = itemsRaw.values
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
    }
    return result;
  }

  // ── Language Preference ──────────────────────────────────────────────

  static Future<void> saveLanguage(String lang) async {
    await _patch('$_usersPath.json', {'language': lang});
  }

  static Future<String> getLanguage() async {
    final profile = await getProfile();
    return (profile?['language'] as String?) ?? 'en';
  }

  // ── Default Source Preference ──────────────────────────────────────────

  static Future<void> saveDefaultSource(String sourceName) async {
    await _patch('$_usersPath.json', {'defaultSource': sourceName});
  }

  static Future<String> getDefaultSource() async {
    final profile = await getProfile();
    return (profile?['defaultSource'] as String?) ?? 'Hong Niu';
  }

  // ── Low-level REST helpers ───────────────────────────────────────────

  static Future<Map<String, dynamic>?> _get(String url) async {
    if (!await AuthService.ensureValidToken()) return null;
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body is Map<String, dynamic>) return body;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _put(String url, Map<String, dynamic>? data) async {
    if (!await AuthService.ensureValidToken()) return;
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      await http.put(uri, headers: _headers, body: json.encode(data));
    } catch (_) {}
  }

  static Future<void> _patch(String url, Map<String, dynamic> data) async {
    if (!await AuthService.ensureValidToken()) return;
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      await http.patch(uri, headers: _headers, body: json.encode(data));
    } catch (_) {}
  }
}
