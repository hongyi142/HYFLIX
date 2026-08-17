import 'package:flutter/foundation.dart';
import '../models/download_item.dart';
import 'web_download.dart';

export '../models/download_item.dart';

/// Web-compatible DownloadService that triggers browser downloads for direct file URLs.
class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  List<DownloadItem> get items => [];
  List<DownloadItem> get completedDownloads => [];
  List<DownloadItem> get activeDownloads => [];

  Future<void> init() async {}

  bool isDownloaded(String contentId, int episodeIndex) => false;

  DownloadItem? getDownload(String contentId, int episodeIndex) => null;

  String? getLocalPath(String contentId, int episodeIndex) => null;

  Future<void> startDownload({
    required String contentId,
    required String contentTitle,
    required int episodeIndex,
    required String episodeName,
    required String m3u8Url,
    String? thumbnailUrl,
  }) async {
    final cleanTitle = contentTitle.replaceAll(RegExp(r'[^\w\s\.-]'), '').replaceAll(' ', '_');
    final cleanEp = episodeName.replaceAll(RegExp(r'[^\w\s\.-]'), '').replaceAll(' ', '_');
    final fileName = '${cleanTitle}_$cleanEp.mp4';
    triggerBrowserDownload(m3u8Url, fileName);
  }

  Future<void> cancelDownload(String contentId, int episodeIndex) async {}

  Future<void> deleteDownload(String contentId, int episodeIndex) async {}

  Future<void> retryDownload({
    required String contentId,
    required String contentTitle,
    required int episodeIndex,
    required String episodeName,
    required String m3u8Url,
    String? thumbnailUrl,
  }) async {
    await startDownload(
      contentId: contentId,
      contentTitle: contentTitle,
      episodeIndex: episodeIndex,
      episodeName: episodeName,
      m3u8Url: m3u8Url,
      thumbnailUrl: thumbnailUrl,
    );
  }

  Future<int> getDownloadSize(String contentId, int episodeIndex) async => 0;
}
