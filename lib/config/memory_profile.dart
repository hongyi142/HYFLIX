import 'dart:io';
import 'package:flutter/foundation.dart';

/// Memory profile configuration for HyFLIX.
/// Allows fine-tuned memory budgeting between standard devices and low-RAM hardware (e.g. 1GB Projectors).
class MemoryProfile {
  final bool isProjector;

  const MemoryProfile({
    this.isProjector = false,
  });

  static MemoryProfile _current = const MemoryProfile();
  static MemoryProfile get current => _current;

  static void init({bool isProjector = false}) {
    _current = MemoryProfile(isProjector: isProjector);
    debugPrint('[MemoryProfile] Initialized: isProjector=$isProjector, '
        'torrentCache=${_current.torrentMaxCacheBytes ~/ (1024 * 1024)}MB, '
        'mpvDemuxer=${_current.mpvDemuxerMaxBytes ~/ (1024 * 1024)}MB');
  }

  /// Max piece cache in bytes for libtorrent streaming.
  /// 20MB for 1GB Projector (avoids native OOM), 32MB for standard Android, 256MB for desktop.
  int get torrentMaxCacheBytes {
    if (isProjector) return 20 * 1024 * 1024; // 20 MB
    if (!kIsWeb && Platform.isAndroid) return 32 * 1024 * 1024; // 32 MB
    return 256 * 1024 * 1024; // 256 MB
  }

  /// Initial preload cache bytes for libtorrent before starting playback.
  int get torrentPreloadBytes {
    if (isProjector) return 4 * 1024 * 1024; // 4 MB
    if (!kIsWeb && Platform.isAndroid) return 16 * 1024 * 1024; // 16 MB
    return 32 * 1024 * 1024; // 32 MB
  }

  /// Max concurrent P2P connections for libtorrent.
  int get torrentConnectionsLimit {
    if (isProjector) return 20;
    if (!kIsWeb && Platform.isAndroid) return 35;
    return 120;
  }

  /// Preload cache percentage for libtorrent session.
  int get torrentPreloadCacheCount {
    if (isProjector) return 10;
    if (!kIsWeb && Platform.isAndroid) return 25;
    return 40;
  }

  /// MPV Demuxer maximum cache size in bytes.
  int get mpvDemuxerMaxBytes {
    if (isProjector) return 16 * 1024 * 1024; // 16 MB
    if (!kIsWeb && Platform.isAndroid) return 64 * 1024 * 1024; // 64 MB
    return 500 * 1024 * 1024; // 500 MB
  }

  /// MPV Demuxer maximum back-buffer size in bytes.
  int get mpvDemuxerMaxBackBytes {
    if (isProjector) return 4 * 1024 * 1024; // 4 MB
    if (!kIsWeb && Platform.isAndroid) return 16 * 1024 * 1024; // 16 MB
    return 100 * 1024 * 1024; // 100 MB
  }

  /// Demuxer readahead window in seconds.
  int get mpvDemuxerReadaheadSecs {
    if (isProjector) return 10;
    if (!kIsWeb && Platform.isAndroid) return 25;
    return 60;
  }

  /// Stream buffer size (socket buffer) in bytes.
  int get mpvStreamBufferSize {
    if (isProjector) return 1 * 1024 * 1024; // 1 MB
    if (!kIsWeb && Platform.isAndroid) return 2 * 1024 * 1024; // 2 MB
    return 4 * 1024 * 1024; // 4 MB
  }

  /// Whether to allow background video hover preview players in movie cards.
  bool get enableVideoPreviews => !isProjector;

  /// Max Flutter image cache size in bytes.
  int get flutterImageCacheLimitBytes {
    if (isProjector) return 15 * 1024 * 1024; // 15 MB
    return 100 * 1024 * 1024; // 100 MB
  }

  /// Max number of images in Flutter image cache.
  int get flutterImageCacheMaxCount {
    if (isProjector) return 80;
    return 1000;
  }

  /// Poster thumbnail decode width limit in pixels.
  /// If set, downsamples decoded bitmap in RAM to fit card dimensions.
  int? get posterImageCacheWidth {
    if (isProjector) return 220;
    return null; // Full resolution decode on standard devices
  }

  /// Hero backdrop decode width limit in pixels.
  int? get heroBackdropCacheWidth {
    if (isProjector) return 850;
    return null;
  }
}
