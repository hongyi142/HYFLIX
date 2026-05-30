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
