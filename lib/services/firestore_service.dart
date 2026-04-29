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
    int episodeIndex = 0,
    int positionSeconds = 0,
  }) async {
    final safeId = contentId.replaceAll(RegExp(r'[.\#\$\[\]]'), '_');
    await _put('$_usersPath/watchHistory/$safeId.json', {
      'title': title,
      'originalTitle': originalTitle,
      'posterUrl': posterUrl,
      'progress': progress,
      'episodeIndex': episodeIndex,
      'positionSeconds': positionSeconds,
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

  // ── Intro Timestamps ───────────────────────────────────────────────

  static Future<void> saveIntroTimestamp({
    required String contentId,
    required int startSeconds,
    required int endSeconds,
  }) async {
    final safeId = contentId.replaceAll(RegExp(r'[.\#\$\[\]]'), '_');
    await _put('$_usersPath/skipIntros/$safeId.json', {
      'startSeconds': startSeconds,
      'endSeconds': endSeconds,
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

  // ── Low-level REST helpers ───────────────────────────────────────────

  static Future<Map<String, dynamic>?> _get(String url) async {
    if (!await AuthService.ensureValidToken()) {
      print('RTDB GET: no valid token');
      return null;
    }
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body is Map<String, dynamic>) return body;
        return null;
      }
      print('RTDB GET failed: ${res.statusCode} ${res.body}');
    } catch (e) {
      print('RTDB GET error: $e');
    }
    return null;
  }

  static Future<void> _put(String url, Map<String, dynamic> data) async {
    if (!await AuthService.ensureValidToken()) {
      print('RTDB PUT: no valid token');
      return;
    }
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      final res = await http.put(uri, headers: _headers, body: json.encode(data));
      if (res.statusCode != 200) {
        print('RTDB PUT failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      print('RTDB PUT error: $e');
    }
  }

  static Future<void> _patch(String url, Map<String, dynamic> data) async {
    if (!await AuthService.ensureValidToken()) {
      print('RTDB PATCH: no valid token');
      return;
    }
    try {
      final uri = Uri.parse('$url?auth=${AuthService.idToken}');
      final res = await http.patch(uri, headers: _headers, body: json.encode(data));
      if (res.statusCode != 200) {
        print('RTDB PATCH failed: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      print('RTDB PATCH error: $e');
    }
  }
}
