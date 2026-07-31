class TorrentStream {
  final String infoHash;
  final String? url; // Direct-play HTTPS url if resolved via Debrid
  final String title;
  final String quality;
  final int seeders;
  final String size;
  final int fileIdx;
  final bool isHDR;
  final String filename;
  final String source;
  final bool isTorBoxCached;

  const TorrentStream({
    required this.infoHash,
    this.url,
    required this.title,
    required this.quality,
    required this.seeders,
    required this.size,
    required this.fileIdx,
    required this.isHDR,
    required this.filename,
    this.source = '',
    this.isTorBoxCached = false,
  });

  String get magnetUri =>
      'magnet:?xt=urn:btih:$infoHash'
      '&tr=udp://tracker.opentrackr.org:1337/announce'
      '&tr=udp://open.stealth.si:80/announce'
      '&tr=udp://tracker.openbittorrent.com:6969/announce'
      '&tr=udp://tracker.torrent.eu.org:451/announce'
      '&tr=udp://explodie.org:6969/announce'
      '&tr=udp://tracker.moeking.me:6969/announce'
      '&tr=udp://tracker.dler.org:6969/announce'
      '&tr=udp://exodus.desync.com:6969/announce'
      '&tr=udp://tracker.tiny-vps.com:6969/announce'
      '&tr=udp://tracker.auctor.tv:6969/announce'
      '&tr=udp://open.demonii.com:1337/announce'
      '&tr=udp://tracker.theoks.net:6969/announce'
      '&tr=udp://tracker.qu.ax:6969/announce'
      '&tr=udp://tracker-udp.gbitt.info:80/announce'
      '&tr=https://tracker.zhuqiy.com:443/announce'
      '&tr=https://tracker.moeking.me:443/announce'
      '&tr=https://tracker.nekomi.cn:443/announce';
  TorrentStream copyWith({
    String? infoHash,
    String? url,
    String? title,
    String? quality,
    int? seeders,
    String? size,
    int? fileIdx,
    bool? isHDR,
    String? filename,
    String? source,
    bool? isTorBoxCached,
  }) {
    return TorrentStream(
      infoHash: infoHash ?? this.infoHash,
      url: url ?? this.url,
      title: title ?? this.title,
      quality: quality ?? this.quality,
      seeders: seeders ?? this.seeders,
      size: size ?? this.size,
      fileIdx: fileIdx ?? this.fileIdx,
      isHDR: isHDR ?? this.isHDR,
      filename: filename ?? this.filename,
      source: source ?? this.source,
      isTorBoxCached: isTorBoxCached ?? this.isTorBoxCached,
    );
  }
}
