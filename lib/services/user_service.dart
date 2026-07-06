import 'firestore_service.dart';

class UserService {
  static Future<void> createProfile({
    required String email,
    required String displayName,
  }) async {
    await FirestoreService.createProfile(email: email, displayName: displayName);
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    return await FirestoreService.getProfile();
  }

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
    String videoSourceName = '',
  }) async {
    await FirestoreService.saveWatchHistory(
      contentId: contentId,
      title: title,
      posterUrl: posterUrl,
      progress: progress,
      originalTitle: originalTitle,
      tmdbId: tmdbId,
      episodeIndex: episodeIndex,
      positionSeconds: positionSeconds,
      m3u8Url: m3u8Url,
      episodes: episodes,
      episodeCount: episodeCount,
      seasonNumber: seasonNumber,
      videoSourceName: videoSourceName,
    );
  }

  static Future<List<Map<String, dynamic>>> getWatchHistory() async {
    return await FirestoreService.getWatchHistory();
  }

  static Future<void> addWatchTime(int seconds) async {
    await FirestoreService.addWatchTime(seconds);
  }

  static Future<int> getWatchTimeSeconds() async {
    return await FirestoreService.getWatchTimeSeconds();
  }

  static Future<void> toggleFavourite(String contentId) async {
    await FirestoreService.toggleFavourite(contentId);
  }

  static Future<bool> isFavourite(String contentId) async {
    return await FirestoreService.isFavourite(contentId);
  }

  static Future<List<String>> getFavouriteIds() async {
    return await FirestoreService.getFavouriteIds();
  }

  static Future<void> updateDisplayName(String displayName) async {
    await FirestoreService.updateDisplayName(displayName);
  }

  static Future<void> updateEmail(String email) async {
    await FirestoreService.updateEmail(email);
  }

  static Future<void> updatePhotoBase64(String? base64) async {
    await FirestoreService.updatePhotoBase64(base64);
  }

  static Future<void> clearWatchHistory() async {
    await FirestoreService.clearWatchHistory();
  }

  static Future<void> saveIntroTimestamp({
    required String contentId,
    required int skipDuration,
  }) async {
    await FirestoreService.saveIntroTimestamp(
      contentId: contentId,
      skipDuration: skipDuration,
    );
  }

  static Future<Map<String, dynamic>?> getIntroTimestamp(String contentId) async {
    return await FirestoreService.getIntroTimestamp(contentId);
  }

  static Future<void> deleteIntroTimestamp(String contentId) async {
    await FirestoreService.deleteIntroTimestamp(contentId);
  }

  static Future<void> saveLanguage(String lang) async {
    await FirestoreService.saveLanguage(lang);
  }

  static Future<String> getLanguage() async {
    return await FirestoreService.getLanguage();
  }

  static Future<void> saveDefaultSource(String sourceName) async {
    await FirestoreService.saveDefaultSource(sourceName);
  }

  static Future<String> getDefaultSource() async {
    return await FirestoreService.getDefaultSource();
  }

  static Future<void> saveEnableTorrent(bool enabled) async {
    await FirestoreService.saveEnableTorrent(enabled);
  }

  static Future<bool> getEnableTorrent() async {
    return await FirestoreService.getEnableTorrent();
  }

  // ── Watchlists ───────────────────────────────────────────────────────

  static Future<void> saveWatchlist(String listName, List<Map<String, dynamic>> items) async {
    await FirestoreService.saveWatchlist(listName, items);
  }

  static Future<void> addToList(String listName, Map<String, dynamic> item) async {
    await FirestoreService.addToList(listName, item);
  }

  static Future<void> removeFromList(String listName, String title) async {
    await FirestoreService.removeFromList(listName, title);
  }

  static Future<void> deleteWatchlist(String listName) async {
    await FirestoreService.deleteWatchlist(listName);
  }

  static Future<Map<String, List<Map<String, dynamic>>>> getWatchlists() async {
    return await FirestoreService.getWatchlists();
  }
}
