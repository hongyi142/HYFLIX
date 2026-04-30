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
    int episodeIndex = 0,
    int positionSeconds = 0,
  }) async {
    await FirestoreService.saveWatchHistory(
      contentId: contentId,
      title: title,
      posterUrl: posterUrl,
      progress: progress,
      originalTitle: originalTitle,
      episodeIndex: episodeIndex,
      positionSeconds: positionSeconds,
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
}
