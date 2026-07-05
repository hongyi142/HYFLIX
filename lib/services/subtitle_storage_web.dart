import 'package:shared_preferences/shared_preferences.dart';
import 'subtitle_storage.dart';

SubtitleStorage getSubtitleStorage() => WebSubtitleStorage();

class WebSubtitleStorage implements SubtitleStorage {
  String _listKey(String tmdbId, int season) => 'subtitles_list_${tmdbId}_s$season';
  String _contentKey(String tmdbId, int season, String fileName) =>
      'subtitle_content_${tmdbId}_s${season}_$fileName';

  @override
  Future<void> saveSubtitle({
    required String tmdbId,
    required int season,
    required String fileName,
    required String content,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Add to list of files
    final listKey = _listKey(tmdbId, season);
    final currentList = prefs.getStringList(listKey) ?? [];
    if (!currentList.contains(fileName)) {
      currentList.add(fileName);
      await prefs.setStringList(listKey, currentList);
    }

    // Save actual content
    final contentKey = _contentKey(tmdbId, season, fileName);
    await prefs.setString(contentKey, content);
  }

  @override
  Future<List<Map<String, dynamic>>> loadSubtitles({
    required String tmdbId,
    required int season,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final listKey = _listKey(tmdbId, season);
    final files = prefs.getStringList(listKey) ?? [];

    final results = <Map<String, dynamic>>[];
    for (final fileName in files) {
      results.add({
        'fileName': fileName,
        'localPath': _contentKey(tmdbId, season, fileName),
      });
    }
    return results;
  }

  @override
  Future<String?> readSubtitle(String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(localPath);
  }

  @override
  Future<void> deleteSubtitles({
    required String tmdbId,
    required int season,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final listKey = _listKey(tmdbId, season);
    final files = prefs.getStringList(listKey) ?? [];

    for (final fileName in files) {
      final contentKey = _contentKey(tmdbId, season, fileName);
      await prefs.remove(contentKey);
    }
    await prefs.remove(listKey);
  }
}
