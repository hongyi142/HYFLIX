import '../models/torrent_stream.dart';

export '../models/torrent_stream.dart';

/// No-op TorrentService for web platform where libtorrent is unavailable.
class TorrentService {
  static final TorrentService _instance = TorrentService._internal();
  factory TorrentService() => _instance;
  TorrentService._internal();

  Future<List<TorrentStream>> fetchStreams(
    String imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async => [];

  Future<(String, int)?> startStream(TorrentStream stream) async => null;

  Future<bool> waitForBuffer(
    int streamId, {
    double targetBufferSeconds = 10.0,
    Duration timeout = const Duration(seconds: 20),
  }) async => false;

  Stream<Map<int, dynamic>>? get streamUpdates => null;

  Future<void> stopStream() async {}

  Future<TorrentStream?> fetchBestStream(
    String imdbId,
    String mediaType, {
    int? season,
    int? episode,
  }) async => null;

  Map<String, dynamic>? getStreamStats() => null;

  int? get activeTorrentId => null;

  Future<void> dispose() async {}
}
