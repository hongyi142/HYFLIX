import 'subtitle_storage_stub.dart'
    if (dart.library.html) 'subtitle_storage_web.dart'
    if (dart.library.io) 'subtitle_storage_native.dart';

abstract class SubtitleStorage {
  static SubtitleStorage? _instance;
  static SubtitleStorage get instance {
    _instance ??= getSubtitleStorage();
    return _instance!;
  }

  Future<void> saveSubtitle({
    required String tmdbId,
    required int season,
    required String fileName,
    required String content,
  });

  Future<List<Map<String, dynamic>>> loadSubtitles({
    required String tmdbId,
    required int season,
  });

  Future<String?> readSubtitle(String localPath);

  Future<void> deleteSubtitles({
    required String tmdbId,
    required int season,
  });
}
