import 'package:flutter/foundation.dart';
import '../models/download_item.dart';

export '../models/download_item.dart';

/// No-op DownloadService for web platform where downloads are not supported.
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
  }) async {}

  Future<void> cancelDownload(String contentId, int episodeIndex) async {}

  Future<void> deleteDownload(String contentId, int episodeIndex) async {}

  Future<void> retryDownload({
    required String contentId,
    required String contentTitle,
    required int episodeIndex,
    required String episodeName,
    required String m3u8Url,
    String? thumbnailUrl,
  }) async {}

  Future<int> getDownloadSize(String contentId, int episodeIndex) async => 0;
}
