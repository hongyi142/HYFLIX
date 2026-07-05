import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'subtitle_storage.dart';

SubtitleStorage getSubtitleStorage() => NativeSubtitleStorage();

class NativeSubtitleStorage implements SubtitleStorage {
  Future<Directory> _localSubsDir(String tmdbId, int season) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/subtitles/${tmdbId}_s$season');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<void> saveSubtitle({
    required String tmdbId,
    required int season,
    required String fileName,
    required String content,
  }) async {
    final dir = await _localSubsDir(tmdbId, season);
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
  }

  @override
  Future<List<Map<String, dynamic>>> loadSubtitles({
    required String tmdbId,
    required int season,
  }) async {
    final dir = await _localSubsDir(tmdbId, season);
    if (!dir.existsSync()) return [];

    final files = dir.listSync().whereType<File>().where(
          (f) => f.path.toLowerCase().endsWith('.srt'),
        );

    final results = <Map<String, dynamic>>[];
    for (final f in files) {
      final baseName = f.path.split(RegExp(r'[/\\]')).last;
      results.add({
        'fileName': baseName,
        'localPath': f.path,
      });
    }
    return results;
  }

  @override
  Future<String?> readSubtitle(String localPath) async {
    final file = File(localPath);
    if (!file.existsSync()) return null;
    return await file.readAsString();
  }

  @override
  Future<void> deleteSubtitles({
    required String tmdbId,
    required int season,
  }) async {
    final dir = await _localSubsDir(tmdbId, season);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
