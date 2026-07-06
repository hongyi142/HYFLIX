import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../models/episode.dart';
import '../services/subtitle_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/torrent_service.dart';
import '../widgets/buttons.dart';
import 'fullscreen_stub.dart'
    if (dart.library.html) 'fullscreen_web.dart';
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String originalTitle;
  final List<Episode> episodes;
  final int initialEpisodeIndex;
  final String? tmdbId;
  final bool isTvShow;
  final int? seasonNumber;
  final int? episodeNumber;
  final String posterUrl;
  final int seekToSeconds;
  final TorrentStream? torrentStream;
  /// Total episode count for torrent TV shows (episodes list is empty for torrents).
  final int episodeCount;
  final String? videoSourceName;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.originalTitle = '',
    this.episodes = const [],
    this.initialEpisodeIndex = 0,
    this.tmdbId,
    this.isTvShow = false,
    this.seasonNumber,
    this.episodeNumber,
    this.posterUrl = '',
    this.seekToSeconds = 0,
    this.torrentStream,
    this.episodeCount = 0,
    this.videoSourceName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  bool _showEpisodes = false;
  bool _showSubtitles = false;
  bool _showStats = false;
  bool _showSettings = false;
  bool _hasError = false;

  // Subtitle custom styles
  double _subFontSize = 28.0;
  Color _subColor = Colors.white;
  double _subBgOpacity = 0.85;
  Color _subBgColor = const Color(0xDD000000);
  double _subPositionOffset = 14.0;
  double _subHorizontalPadding = 24.0;

  // Subtitle cover mask settings
  bool _showSubMask = false;
  double _subMaskWidthPct = 0.8;
  double _subMaskHeight = 50.0;
  double _subMaskPosition = 10.0;
  double _subMaskOpacity = 1.0;
  late int _currentEpIndex;
  String? _currentTitle;
  List<SubtitleItem> _availableSubs = [];
  SubtitleItem? _selectedSub;
  bool _loadingSubs = false;
  DateTime? _startTime;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _positionSub;
  Map<String, dynamic>? _introTimestamp;
  bool _showSkipIntro = false;
  bool _isFullScreen = false;

  // Hold-to-speed state
  bool _isLongPressSpeed = false;

  // Torrent state
  bool _isTorrentBuffering = false;
  String _torrentStatus = '';
  Timer? _statsTimer;
  Map<String, dynamic>? _torrentStats;
  Map<String, dynamic>? _streamBufferInfo;
  StreamSubscription<Map<int, dynamic>>? _streamInfoSub;
  String? _torrentUrl;

  // Next episode autoplay
  bool _showAutoplay = false;
  int _autoplayCountdown = 60;
  bool _autoPlaying = false;
  bool _autoplayDismissed = false;
  Timer? _autoplayTimer;
  StreamSubscription<bool>? _completedSub;

  // Audio tracks
  bool _showAudioTracks = false;
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _selectedAudioTrack;
  StreamSubscription<Tracks>? _audioTracksSub;

  // Exit guard
  bool _isExiting = false;

  // Scrubbing state — prevents seek on every drag pixel
  bool _isSeeking = false;
  double _seekValue = 0.0;

  // Seek recovery for torrent streams
  Timer? _seekRecoveryTimer;

  // Periodic save during playback (crash protection)
  Timer? _periodicSaveTimer;

  /// Effective episode count: uses episodes list length if available,
  /// otherwise falls back to episodeCount param (for torrent content).
  int get _effectiveEpisodeCount =>
      widget.episodes.isNotEmpty ? widget.episodes.length : widget.episodeCount;

  /// Whether this is a multi-episode TV show (VOD or torrent).
  bool get _hasMultipleEpisodes => _effectiveEpisodeCount > 1;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _currentEpIndex = widget.initialEpisodeIndex;
    _currentTitle = widget.originalTitle.isNotEmpty ? widget.originalTitle : widget.title;
    _player = Player();
    _controller = VideoController(_player);

    if (widget.torrentStream != null) {
      _startTorrentPlayback();
    } else {
      _openMedia(widget.videoUrl, seekToSeconds: widget.seekToSeconds);
    }

    _loadIntroTimestamp();
    _loadSubtitleSettings();
    _listenPosition();
    _setupAutoplay();
    _listenAudioTracks();
    _scheduleHideControls();

    // Save watch progress every 30 seconds as crash protection
    _periodicSaveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _periodicSave(),
    );
  }

  /// Start torrent playback — show buffering overlay while metadata downloads.
  Future<void> _startTorrentPlayback() async {
    final stream = widget.torrentStream!;

    // Check if we have a direct debrid play link
    if (stream.url != null && stream.url!.isNotEmpty) {
      debugPrint('[VideoPlayer] Starting debrid direct stream: ${stream.url}');
      setState(() {
        _isTorrentBuffering = true;
        _torrentStatus = 'Opening TorBox stream...';
      });

      // Listen to buffering state changes for status text
      _bufferingSub = _player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isTorrentBuffering = buffering;
            if (buffering) {
              _torrentStatus = 'Buffering...';
            } else {
              _seekRecoveryTimer?.cancel();
            }
          });
        }
      });

      _torrentUrl = stream.url;

      if (!mounted) return;
      setState(() {
        _isTorrentBuffering = false;
        _torrentStatus = '';
      });

      // Configure mpv for direct streaming
      try {
        final native = _player.platform as NativePlayer;
        await native.setProperty('network-timeout', '60');
        await native.setProperty('user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        await native.setProperty('cache-secs', '60');
        await native.setProperty('demuxer-readahead-secs', '60');
      } catch (e) {
        debugPrint('[VideoPlayer] Failed to configure mpv: $e');
      }

      _openMedia(stream.url!, seekToSeconds: widget.seekToSeconds);
      _fetchSubtitles();
      return;
    }

    debugPrint('[VideoPlayer] Starting torrent: ${stream.quality} '
        'hash=${stream.infoHash.substring(0, 16)}... fileIdx=${stream.fileIdx}');

    setState(() {
      _isTorrentBuffering = true;
      _torrentStatus = 'Connecting to peers...';
    });

    // Listen to buffering state changes for status text
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() {
          if (buffering) {
            _torrentStatus = 'Buffering...';
          }
        });
      }
    });

    // Update torrent stats periodically (only for P2P)
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {
          _torrentStats = TorrentService().getStreamStats();
          // Update status text based on stats
          if (_torrentStats != null && _isTorrentBuffering) {
            final rate = _torrentStats!['downloadRate'] as int? ?? 0;
            if (rate > 0) {
              _torrentStatus = 'Downloading... ${_formatBytes(rate)}/s';
            }
          }
        });
      }
    });

    final result = await TorrentService().startStream(stream);
    if (!mounted) return;

    if (result == null) {
      debugPrint('[VideoPlayer] Torrent stream failed');
      setState(() {
        _isTorrentBuffering = false;
        _hasError = true;
      });
      return;
    }

    final (url, streamId) = result;
    _torrentUrl = url;

    // Subscribe to stream updates for real-time buffer info in the overlay
    _streamInfoSub = TorrentService().streamUpdates?.listen((streams) {
      if (!mounted) return;
      final info = streams[streamId];
      if (info != null) {
        setState(() {
          _streamBufferInfo = {
            'bufferSeconds': info.bufferSeconds,
            'bufferPieces': info.bufferPieces,
            'readaheadWindow': info.readaheadWindow,
            'bufferPct': info.bufferPct,
            'downloadRate': info.downloadRate,
          };
        });
      }
    });

    // Update status while waiting for buffer
    setState(() {
      _torrentStatus = 'Preparing stream...';
    });

    // Wait for buffer to reach 10 seconds of video (or timeout after 20s)
    // For 4K, this ensures enough data is buffered before mpv starts reading
    final bufferReady = await TorrentService().waitForBuffer(
      streamId,
      targetBufferSeconds: 10.0,
      timeout: const Duration(seconds: 20),
    );

    if (!mounted) return;

    debugPrint('[VideoPlayer] Buffer ready: $bufferReady, opening media');
    // Keep _streamInfoSub alive so the stats panel shows live buffer info
    setState(() {
      _isTorrentBuffering = false;
      _torrentStatus = '';
    });

    await _configureMpvForTorrent();
    _openMedia(url, seekToSeconds: widget.seekToSeconds);
    _fetchSubtitles();
  }

  /// Configure mpv for torrent streaming — increase timeouts and enable
  /// readahead so seeking into unbuffered regions doesn't cause a stall.
  Future<void> _configureMpvForTorrent() async {
    try {
      final native = _player.platform as NativePlayer;
      // Default is 5s; torrent HTTP server can block up to 60s waiting for pieces
      await native.setProperty('network-timeout', '60');
      // Keep 60s of video cached ahead of the playhead
      await native.setProperty('cache-secs', '60');
      // Demuxer readahead window — mpv prefetches data this far ahead
      await native.setProperty('demuxer-readahead-secs', '60');
      debugPrint('[VideoPlayer] Configured mpv for torrent streaming');
    } catch (e) {
      debugPrint('[VideoPlayer] Failed to configure mpv for torrent: $e');
    }
  }

  /// Start a recovery timer for torrent seeks. If the player is still
  /// buffering after [timeout], reopen the media at the seek target position.
  /// This handles the case where mpv's HTTP connection stalls because the
  /// torrent piece at the seek position isn't available yet.
  void _startSeekRecovery(Duration target, {Duration timeout = const Duration(seconds: 15)}) {
    _seekRecoveryTimer?.cancel();
    if (widget.torrentStream == null || _torrentUrl == null) return;

    _seekRecoveryTimer = Timer(timeout, () async {
      if (!mounted) return;
      // If still buffering after the timeout, reopen at the target position
      if (_isTorrentBuffering || _player.state.buffering) {
        debugPrint('[VideoPlayer] Seek recovery: reopening at ${target.inSeconds}s');
        setState(() {
          _isTorrentBuffering = true;
          _torrentStatus = 'Reconnecting...';
        });
        await _openMedia(_torrentUrl!, seekToSeconds: target.inSeconds);
      }
    });
  }

  Future<void> _openMedia(String url, {int seekToSeconds = 0}) async {
    try {
      debugPrint('[VideoPlayer] Opening media: $url');
      _bufferingSub?.cancel();

      // Configure mpv timeout for VOD streams. Chinese VOD CDNs can be slow
      // so we raise the network timeout. We do NOT set cache-secs or
      // demuxer-readahead-secs here — mpv's defaults (120s / 150s) are much
      // more generous than the 30s we were using, and that was causing
      // stuttering on Chinese VOD streams.
      if (widget.torrentStream == null) {
        final native = _player.platform as NativePlayer;
        await native.setProperty('network-timeout', '60');
        await native.setProperty('user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      }

      await _player.open(Media(url));
      debugPrint('[VideoPlayer] Media opened successfully');

      // Listen to buffering state for debug logging and UI updates
      _bufferingSub = _player.stream.buffering.listen((buffering) {
        debugPrint('[VideoPlayer] Buffering: $buffering');
        if (mounted) {
          setState(() {
            if (widget.torrentStream != null) {
              _isTorrentBuffering = buffering;
              if (buffering) {
                _torrentStatus = 'Buffering...';
              } else {
                // Playback recovered — cancel seek recovery timer
                _seekRecoveryTimer?.cancel();
              }
            }
          });
        }
      });

      if (seekToSeconds > 0) {
        // Wait for buffering to finish, then seek and play
        bool hasStarted = false;
        _bufferingSub = _player.stream.buffering.listen((buffering) {
          if (!buffering && !hasStarted && mounted) {
            hasStarted = true;
            _player.seek(Duration(seconds: seekToSeconds));
            _player.play();
            _bufferingSub?.cancel();
          }
        });
        // Also try immediate seek in case player is already ready
        await _player.seek(Duration(seconds: seekToSeconds));
      } else {
        // Autoplay — ensure video starts playing
        _player.play();
      }
      _fetchSubtitles();
    } catch (e, st) {
      debugPrint('[VideoPlayer] Error opening media: $e\n$st');
      if (mounted) setState(() => _hasError = true);
    }
  }

  /// Series-level content ID for intro timestamps (same across all episodes).
  String get _seriesContentId => widget.tmdbId ?? widget.originalTitle;

  Future<void> _loadIntroTimestamp() async {
    final data = await UserService.getIntroTimestamp(_seriesContentId);
    if (data != null && mounted) {
      setState(() => _introTimestamp = data);
    }
  }

  void _listenPosition() {
    _positionSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      final sec = pos.inSeconds;
      bool shouldShow = false;

      // Hide skip/record intro after the first 3 minutes
      if (sec < 180) {
        if (_introTimestamp != null) {
          final skipDur = (_introTimestamp!['skipDuration'] as num?)?.toInt() ??
                          (_introTimestamp!['endSeconds'] as num?)?.toInt() ?? 0;
          shouldShow = sec < skipDur;
        } else {
          shouldShow = true;
        }
      }

      if (shouldShow != _showSkipIntro) {
        setState(() => _showSkipIntro = shouldShow);
      }

      // Also check autoplay on every position change (responsive to seeks)
      _checkAutoplay();
    });
  }

  /// Evaluate whether the autoplay next-episode card should be shown.
  /// Called from both the periodic timer and the position listener so the
  /// card appears immediately after a seek, not just on the next tick.
  void _checkAutoplay() {
    if (!mounted || _autoPlaying || _autoplayDismissed) return;
    final hasEpisodes = _hasMultipleEpisodes;
    final hasNext = _currentEpIndex < _effectiveEpisodeCount - 1;
    if (!hasEpisodes || !hasNext) return;

    final pos = _player.state.position.inSeconds;
    final dur = _player.state.duration.inSeconds;
    if (dur <= 0) return;

    final remaining = dur - pos;

    if (remaining <= 60 && remaining > 0) {
      if (!_showAutoplay) {
        setState(() {
          _showAutoplay = true;
          _autoplayCountdown = 60;
        });
      }
    } else if (remaining > 60 && _showAutoplay) {
      // User seeked away from the end
      setState(() {
        _showAutoplay = false;
        _autoplayCountdown = 60;
      });
    }
  }

  void _setupAutoplay() {
    // Check autoplay every second — handles both detection and countdown.
    // This is the primary trigger; the position listener also calls
    // _checkAutoplay() for instant response during active playback.
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _autoPlaying) return;

      if (!_showAutoplay) {
        // Not showing yet — check if we should start
        _checkAutoplay();
      } else if (_autoplayCountdown > 0) {
        // Card is visible — tick the countdown
        setState(() => _autoplayCountdown--);
        if (_autoplayCountdown <= 0) {
          _playNextEpisode();
        }
      }
    });

    // Auto-advance when playback completes
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed && mounted && !_autoPlaying) {
        // For torrent streams, ignore spurious completed events caused by
        // seeking into unbuffered regions — only advance if near the end.
        if (widget.torrentStream != null) {
          final pos = _player.state.position.inSeconds;
          final dur = _player.state.duration.inSeconds;
          if (dur > 0 && pos < dur - 10) {
            debugPrint('[VideoPlayer] Ignoring spurious completed event '
                '(pos=$pos, dur=$dur)');
            _player.play();
            return;
          }
        }
        final hasNext = _currentEpIndex < _effectiveEpisodeCount - 1;
        if (hasNext) {
          _playNextEpisode();
        }
      }
    });
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    _completedSub?.cancel();
    _completedSub = null;
  }

  void _listenAudioTracks() {
    _audioTracksSub = _player.stream.tracks.listen((tracks) {
      if (!mounted) return;
      final audioTracks = tracks.audio.where((t) => t.id != 'no' && t.id != 'auto').toList();
      setState(() {
        _audioTracks = audioTracks;
        if (audioTracks.length <= 1) _showAudioTracks = false;
      });
    });
  }

  void _selectAudioTrack(AudioTrack track) {
    _player.setAudioTrack(track);
    setState(() {
      _selectedAudioTrack = track;
      _showAudioTracks = false;
    });
  }

  void _playNextEpisode() {
    if (_autoPlaying) return;
    final nextIdx = _currentEpIndex + 1;
    if (nextIdx >= _effectiveEpisodeCount) return;
    _autoPlaying = true;
    _showAutoplay = false;
    _autoplayDismissed = false;
    _autoplayCountdown = 60;
    // For torrent content (no episode URLs), pop with the next episode index
    if (widget.episodes.isEmpty && widget.torrentStream != null) {
      Navigator.of(context).pop(nextIdx);
      return;
    }
    _playEpisode(nextIdx);
  }

  Future<void> _skipIntro() async {
    if (_introTimestamp != null) {
      final skipDur = (_introTimestamp!['skipDuration'] as num?)?.toInt() ??
                      (_introTimestamp!['endSeconds'] as num?)?.toInt() ?? 0;
      _player.seek(Duration(seconds: skipDur));
    }
  }

  Future<void> _recordIntro() async {
    final pos = _player.state.position.inSeconds;
    await UserService.saveIntroTimestamp(
      contentId: _seriesContentId,
      skipDuration: pos,
    );
    if (mounted) {
      setState(() {
        _introTimestamp = {'skipDuration': pos};
      });
    }
  }

  Future<void> _loadSubtitleSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _subFontSize = prefs.getDouble('subtitles_font_size') ?? 28.0;
        final colorVal = prefs.getInt('subtitles_color') ?? 0xFFFFFFFF;
        _subColor = Color(colorVal);
        _subBgOpacity = prefs.getDouble('subtitles_bg_opacity') ?? 0.85;
        _subBgColor = Colors.black.withOpacity(_subBgOpacity);
        _subPositionOffset = prefs.getDouble('subtitles_position') ?? 14.0;
        _subHorizontalPadding = prefs.getDouble('subtitles_horiz_padding') ?? 24.0;

        _showSubMask = prefs.getBool('sub_mask_enabled') ?? false;
        _subMaskWidthPct = prefs.getDouble('sub_mask_width_pct') ?? 0.8;
        _subMaskHeight = prefs.getDouble('sub_mask_height') ?? 50.0;
        _subMaskPosition = prefs.getDouble('sub_mask_position') ?? 10.0;
        _subMaskOpacity = prefs.getDouble('sub_mask_opacity') ?? 1.0;
      });
    } catch (_) {}
  }

  Future<void> _saveSubtitleFontSize(double size) async {
    setState(() => _subFontSize = size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_font_size', size);
  }

  Future<void> _saveSubtitleColor(Color color) async {
    setState(() => _subColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subtitles_color', color.value);
  }

  Future<void> _saveSubtitleBgOpacity(double opacity) async {
    setState(() {
      _subBgOpacity = opacity;
      _subBgColor = Colors.black.withOpacity(opacity);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_bg_opacity', opacity);
  }

  Future<void> _saveSubtitlePosition(double offset) async {
    setState(() => _subPositionOffset = offset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_position', offset);
  }

  Future<void> _saveSubtitleHorizontalPadding(double padding) async {
    setState(() => _subHorizontalPadding = padding);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitles_horiz_padding', padding);
  }

  Future<void> _saveSubMaskEnabled(bool enabled) async {
    setState(() => _showSubMask = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sub_mask_enabled', enabled);
  }

  Future<void> _saveSubMaskWidthPct(double widthPct) async {
    setState(() => _subMaskWidthPct = widthPct);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sub_mask_width_pct', widthPct);
  }

  Future<void> _saveSubMaskHeight(double height) async {
    setState(() => _subMaskHeight = height);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sub_mask_height', height);
  }

  Future<void> _saveSubMaskPosition(double position) async {
    setState(() => _subMaskPosition = position);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sub_mask_position', position);
  }

  Future<void> _saveSubMaskOpacity(double opacity) async {
    setState(() => _subMaskOpacity = opacity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sub_mask_opacity', opacity);
  }

  Future<void> _resetIntro() async {
    await UserService.deleteIntroTimestamp(_seriesContentId);
    if (mounted) {
      setState(() {
        _introTimestamp = null;
        _showSkipIntro = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Intro time reset. You can record a new timestamp on the next skip point.'),
          duration: Duration(seconds: 3),
          backgroundColor: AppTheme.accent,
        ),
      );
    }
  }

  int? _episodeNumberInSeason(int globalIndex) {
    final eps = widget.episodes;
    if (eps.isEmpty) return null;
    final seasonMap = <int, List<Episode>>{};
    for (final ep in eps) {
      final m = RegExp(r'第(\d+)季').firstMatch(ep.name);
      final s = m != null ? int.tryParse(m.group(1)!) ?? 1 : 1;
      seasonMap.putIfAbsent(s, () => []).add(ep);
    }
    final seasonEps = seasonMap[widget.seasonNumber] ?? eps;
    final ep = eps[globalIndex];
    final pos = seasonEps.indexOf(ep);
    return pos >= 0 ? pos + 1 : globalIndex + 1;
  }

  Future<void> _fetchSubtitles() async {
    if (mounted) setState(() => _loadingSubs = true);
    try {
      final currentEpisode = widget.episodes.isNotEmpty ? widget.episodes[_currentEpIndex] : null;
      final epNum = widget.episodeNumber ?? _episodeNumberInSeason(_currentEpIndex);
      final subs = await SubtitleService.searchSubtitles(
        _currentTitle ?? '',
        tmdbId: widget.tmdbId,
        seasonNumber: widget.seasonNumber,
        episodeNumber: epNum,
        episodeName: currentEpisode?.name,
        isTvShow: widget.isTvShow,
      );

      // Load locally stored subtitles (native only)
      List<SubtitleItem> localSubs = [];
      if (!kIsWeb && widget.tmdbId != null && widget.seasonNumber != null) {
        localSubs = await SubtitleService.loadLocalSubtitles(
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
          episodeNumber: epNum,
        );
      }

      SubtitleItem? autoSelectedSub;
      for (final sub in localSubs) {
        if (sub.matchType == SubtitleMatchType.exactEpisode) {
          autoSelectedSub = sub;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _availableSubs = [...localSubs, ...subs];
          _loadingSubs = false;
        });

        // Auto-select matching local subtitle if none is selected yet
        if (autoSelectedSub != null && _selectedSub == null) {
          _selectSubtitle(autoSelectedSub);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  Future<void> _selectSubtitle(SubtitleItem item) async {
    if (mounted) {
      setState(() {
        _selectedSub = item;
        _showSubtitles = false;
      });
    }

    String? srtContent;
    final epNum = widget.episodeNumber ?? _episodeNumberInSeason(_currentEpIndex);
    
    if (item.source == 'local' && item.localPath != null) {
      srtContent = await SubtitleService.readLocalSubtitle(
        item.localPath!,
        episodeNumber: item.matchType == SubtitleMatchType.seasonFallback ? epNum : null,
      );
    } else if (item.matchType == SubtitleMatchType.seasonFallback && epNum != null && widget.tmdbId != null && widget.seasonNumber != null) {
      // Auto-download and unzip season subtitles to local storage
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading and extracting season subtitles...'),
            duration: Duration(seconds: 3),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
      final saved = await SubtitleService.downloadSeasonSubtitles(
        item: item,
        tmdbId: widget.tmdbId!,
        season: widget.seasonNumber!,
      );
      
      if (saved.isNotEmpty) {
        // Refresh subtitle list so local subtitles are shown
        await _fetchSubtitles();
        
        // Find the matching local subtitle for this episode
        final matchingLocal = await SubtitleService.findMatchingLocalSubtitle(
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
          episodeNumber: epNum,
        );
        
        if (matchingLocal != null) {
          // Load the matching local subtitle
          _selectedSub = matchingLocal;
          srtContent = await SubtitleService.readLocalSubtitle(
            matchingLocal.localPath!,
          );
        } else {
          // Fallback to first saved local subtitle if no exact match
          srtContent = await SubtitleService.readLocalSubtitle(
            saved.first.localPath!,
            episodeNumber: epNum,
          );
        }
      } else {
        // Fallback to simple in-memory fetch if download/extract failed
        srtContent = await SubtitleService.fetchAndExtractEpisode(
          item,
          episodeNumber: epNum,
        );
      }
    } else if (item.matchType == SubtitleMatchType.seasonFallback && epNum != null) {
      srtContent = await SubtitleService.fetchAndExtractEpisode(
        item,
        episodeNumber: epNum,
      );
    } else {
      srtContent = await SubtitleService.fetchSubtitleContent(item);
    }

    if (srtContent != null && srtContent.trim().isNotEmpty && mounted) {
      await _player.setSubtitleTrack(SubtitleTrack.data(
        srtContent,
        title: item.fileName,
        language: item.language,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subtitles active: ${item.language.toUpperCase()}'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.accent,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load subtitle content'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _playEpisode(int index) {
    if (index < 0 || index >= _effectiveEpisodeCount) return;
    // For torrent content (no episode URLs), pop with the target episode index
    if (widget.episodes.isEmpty && widget.torrentStream != null) {
      Navigator.of(context).pop(index);
      return;
    }
    final ep = widget.episodes[index];
    setState(() {
      _currentEpIndex = index;
      _hasError = false;
      _showEpisodes = false;
      _showSubtitles = false;
      _showAudioTracks = false;
      _showSettings = false;
      _showAutoplay = false;
      _autoplayDismissed = false;
      _autoplayCountdown = 60;
      _autoPlaying = false;
      _selectedSub = null;
      _selectedAudioTrack = null;
      _availableSubs = [];
    });
    _openMedia(ep.url);
    _loadIntroTimestamp();
  }

  Future<void> _toggleFullScreen() async {
    setState(() => _isFullScreen = !_isFullScreen);
    try {
      await toggleFullScreen();
    } catch (e) {
      debugPrint('[VideoPlayer] Fullscreen toggle error: $e');
      // Revert UI state on failure
      if (mounted) setState(() => _isFullScreen = !_isFullScreen);
    }
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showControls) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  @override
  void dispose() {
    try {
      _cancelAutoplay();
      _periodicSaveTimer?.cancel();
      _seekRecoveryTimer?.cancel();
      _bufferingSub?.cancel();
      _positionSub?.cancel();
      _statsTimer?.cancel();
      _audioTracksSub?.cancel();
      _streamInfoSub?.cancel();
    } catch (e) {
      debugPrint('[VideoPlayer] Error cancelling subscriptions: $e');
    }
    // If _exitPlayer already handled cleanup, it will have stopped the player
    // and torrent before Navigator.pop triggers this dispose. In that case
    // we just need to release the native player object.
    if (!_isExiting) {
      // Framework-driven dispose (e.g. parent route removed) — capture
      // position before stopping so we can save watch progress.
      final position = _player.state.position;
      final duration = _player.state.duration;
      try {
        _player.stop();
      } catch (_) {}
      TorrentService().stopStream().catchError((e) {
        debugPrint('[VideoPlayer] Error stopping torrent in dispose: $e');
      });
      // Fire-and-forget save so progress isn't lost on force-close
      _saveWatchData(position, duration).catchError((e) {
        debugPrint('[VideoPlayer] Error saving watch data in dispose: $e');
      });
    }
    try {
      _player.dispose();
    } catch (e) {
      debugPrint('[VideoPlayer] Error disposing player: $e');
    }
    super.dispose();
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _showSettings = false;
    _cancelAutoplay();
    _periodicSaveTimer?.cancel();
    _statsTimer?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _audioTracksSub?.cancel();
    _streamInfoSub?.cancel();

    // Capture player state before disposal
    final position = _player.state.position;
    final duration = _player.state.duration;

    // Stop the player first so it closes its HTTP connections to the
    // torrent streaming server. If we stop the torrent while the player
    // is still reading, the broken pipe causes a crash.
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[VideoPlayer] Error stopping player: $e');
    }

    // Now safe to tear down the torrent HTTP server
    try {
      await TorrentService().stopStream();
    } catch (e) {
      debugPrint('[VideoPlayer] Error stopping torrent: $e');
    }

    // Save watch data before navigating away
    try {
      await _saveWatchData(position, duration);
    } catch (e) {
      debugPrint('[VideoPlayer] Error saving watch data: $e');
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveWatchData(Duration position, Duration duration) async {
    if (AuthService.uid == null) return;
    final elapsed = _startTime != null ? DateTime.now().difference(_startTime!).inSeconds : 0;
    if (elapsed > 5) {
      await UserService.addWatchTime(elapsed);
    }
    final progress = duration.inSeconds > 0
        ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final currentEp = widget.episodes.isNotEmpty ? widget.episodes[_currentEpIndex] : null;
    if (currentEp != null || widget.videoUrl.isNotEmpty || widget.torrentStream != null) {
      await UserService.saveWatchHistory(
        contentId: widget.tmdbId ?? (widget.originalTitle.isNotEmpty ? widget.originalTitle : widget.title),
        title: widget.title,
        posterUrl: widget.posterUrl,
        progress: progress,
        originalTitle: widget.originalTitle,
        tmdbId: widget.tmdbId ?? '',
        episodeIndex: _currentEpIndex,
        positionSeconds: position.inSeconds,
        m3u8Url: widget.videoUrl,
        episodes: widget.episodes.map((e) => e.toJson()).toList(),
        episodeCount: _effectiveEpisodeCount,
        seasonNumber: widget.seasonNumber ?? 1,
        videoSourceName: widget.videoSourceName ?? '',
      );
    }
  }

  /// Periodically save watch progress during playback (crash protection).
  Future<void> _periodicSave() async {
    if (_isExiting) return;
    try {
      final position = _player.state.position;
      final duration = _player.state.duration;
      if (duration.inSeconds > 0) {
        await _saveWatchData(position, duration);
      }
    } catch (e) {
      debugPrint('[VideoPlayer] Error in periodic save: $e');
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final hasEpisodes = _hasMultipleEpisodes;
    final currentEpName = hasEpisodes
        ? (widget.episodes.isNotEmpty
            ? widget.episodes[_currentEpIndex].name
            : 'Episode ${_currentEpIndex + 1}')
        : widget.title;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _exitPlayer();
      },
      child: KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) _exitPlayer();
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) _player.playOrPause();
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyS && _showSkipIntro) {
          if (_introTimestamp == null) { _recordIntro(); } else { _skipIntro(); }
        }
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final pos = _player.state.position;
          _player.seek(pos - const Duration(seconds: 5));
        }
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowRight) {
          final pos = _player.state.position;
          _player.seek(pos + const Duration(seconds: 5));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
            fit: StackFit.expand,
            children: [
              // IgnorePointer ensures the Video widget never absorbs taps;
              // all gestures are handled by the overlay controls above it.
              IgnorePointer(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),

              if (_showSubMask)
                IgnorePointer(
                  child: Stack(
                    children: [
                      Positioned(
                        bottom: _subMaskPosition,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: MediaQuery.of(context).size.width * _subMaskWidthPct,
                            height: _subMaskHeight,
                            color: Colors.black.withOpacity(_subMaskOpacity),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Render subtitles one layer above the cover mask
              IgnorePointer(
                child: SubtitleView(
                  key: ValueKey('${_subFontSize}_${_subColor.value}_${_subBgOpacity}_${_subPositionOffset}_${_subHorizontalPadding}'),
                  controller: _controller,
                  configuration: SubtitleViewConfiguration(
                    style: TextStyle(
                      fontSize: _subFontSize,
                      color: _subColor,
                      fontWeight: FontWeight.w600,
                      backgroundColor: _subBgColor,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: _subHorizontalPadding,
                      vertical: _subPositionOffset,
                    ),
                  ),
                ),
              ),


              // Tap catcher — sits behind all overlays so tapping the
              // video area toggles controls, but tapping any overlay
              // button/panel is handled by that overlay's own gesture
              // detectors (rendered later → higher z-order).
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_showSubtitles || _showEpisodes || _showStats || _showAudioTracks || _showSettings) {
                    setState(() { 
                      _showSubtitles = false; 
                      _showEpisodes = false; 
                      _showStats = false; 
                      _showAudioTracks = false; 
                      _showSettings = false; 
                    });
                  } else {
                    _toggleControls();
                  }
                },
                onLongPressStart: (_) {
                  if (!_isLongPressSpeed) {
                    setState(() => _isLongPressSpeed = true);
                    _player.setRate(2.0);
                  }
                },
                onLongPressEnd: (_) {
                  if (_isLongPressSpeed) {
                    setState(() => _isLongPressSpeed = false);
                    _player.setRate(1.0);
                  }
                },
                child: const SizedBox.expand(),
              ),

              // Torrent buffering overlay
              if (_isTorrentBuffering)
                _buildBufferingOverlay(),

              // Error state
              if (_hasError)
                _errorWidget(context),

              // Long-press speed indicator
              if (_isLongPressSpeed)
                Positioned(
                  top: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.zap, color: Colors.amber, size: 18),
                          SizedBox(width: 6),
                          Text(
                            '2x Speed',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Controls overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControls(context, currentEpName, hasEpisodes),
                ),
              ),

              // Skip Intro / Record Intro button
              Positioned(
                bottom: 160,
                left: 24,
                child: AnimatedOpacity(
                  opacity: _showSkipIntro ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: _showSkipIntro
                      ? HoverButton(
                          onTap: _introTimestamp == null ? _recordIntro : _skipIntro,
                          backgroundColor: Colors.black.withOpacity(0.7),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _introTimestamp == null ? LucideIcons.circleDot : LucideIcons.skipForward,
                                  color: Colors.white,
                                  size: 16
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _introTimestamp == null ? 'Record Intro Time' : 'Skip Intro',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox(),
                ),
              ),

              // Next episode autoplay card (Netflix-style bottom-right)
              if (_showAutoplay && _hasMultipleEpisodes)
                Positioned(
                  bottom: 160,
                  right: 24,
                  child: _buildAutoplayCard(),
                ),

              // Subtitle panel (slides from right)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: 0, bottom: 0,
                right: _showSubtitles ? 0 : -300,
                width: 300,
                child: _buildSubtitlePanel(),
              ),

              // Audio track panel (slides from right)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: 0, bottom: 0,
                right: _showAudioTracks ? 0 : -300,
                width: 300,
                child: _buildAudioTrackPanel(),
              ),

              // Episode panel (slides from right) — only for VOD with episode list
              if (hasEpisodes && widget.episodes.isNotEmpty)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: 0, bottom: 0,
                  right: _showEpisodes ? 0 : -300,
                  width: 300,
                  child: _buildEpisodePanel(),
                ),

              // Stats panel (slides from top-right)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: _showStats ? 70 : -600,
                right: 20,
                width: 280,
                child: _buildStatsPanel(),
              ),

              // Settings panel (slides from right)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: 0, bottom: 0,
                right: _showSettings ? 0 : -300,
                width: 300,
                child: _buildSettingsPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBufferingOverlay() {
    final bufferInfo = _streamBufferInfo;
    final bufferPct = bufferInfo != null
        ? ((bufferInfo['bufferPct'] as double? ?? 0) * 100).round()
        : 0;
    final bufferSecs = bufferInfo != null
        ? (bufferInfo['bufferSeconds'] as double? ?? 0).toStringAsFixed(1)
        : '0.0';

    return IgnorePointer(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress ring when buffer info is available, indeterminate spinner otherwise
              if (bufferPct > 0)
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: bufferPct / 100,
                        color: AppTheme.accent,
                        backgroundColor: Colors.white12,
                        strokeWidth: 4,
                      ),
                      Text(
                        '$bufferPct%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: AppTheme.accent,
                    strokeWidth: 3,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _torrentStatus.isNotEmpty ? _torrentStatus : 'Loading...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (bufferInfo != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${bufferSecs}s buffered',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_torrentStats != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_formatBytes(_torrentStats!['downloadRate'] ?? 0)}/s  '
                  '·  ${_torrentStats!['numPeers'] ?? 0} peers',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel() {
    final stats = _torrentStats;
    final isTorrent = widget.torrentStream != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Network Stats',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (context, snap) {
                final buffering = snap.data ?? false;
                final status = buffering
                    ? 'Buffering'
                    : (_player.state.playing ? 'Playing' : 'Paused');
                return _statRow('Status', status,
                    color: buffering ? Colors.orange : Colors.green);
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<int?>(
              stream: _player.stream.width,
              builder: (context, wSnap) => StreamBuilder<int?>(
                stream: _player.stream.height,
                builder: (context, hSnap) {
                  final w = wSnap.data ?? _player.state.width;
                  final h = hSnap.data ?? _player.state.height;
                  final res = (w != null && h != null && w > 0 && h > 0)
                      ? '${w}x$h'
                      : 'Detecting...';
                  return _statRow('Resolution', res);
                },
              ),
            ),
            if (isTorrent && widget.torrentStream!.url != null) ...[
              const SizedBox(height: 8),
              _statRow('Type', 'TorBox Direct Play', color: Colors.cyanAccent),
              const SizedBox(height: 8),
              _statRow('Format', 'HTTPS CDN direct play'),
              const SizedBox(height: 8),
              _statRow('Quality', widget.torrentStream!.quality),
              const SizedBox(height: 8),
              _statRow('Size', widget.torrentStream!.size.isNotEmpty ? widget.torrentStream!.size : 'Unknown'),
              const SizedBox(height: 8),
              _statRow('Source', widget.torrentStream!.source),
            ] else if (isTorrent && stats != null) ...[
              const SizedBox(height: 8),
              _statRow('Download', '${_formatBytes(stats['downloadRate'] ?? 0)}/s'),
              const SizedBox(height: 8),
              _statRow('Upload', '${_formatBytes(stats['uploadRate'] ?? 0)}/s'),
              const SizedBox(height: 8),
              _statRow('Peers', '${stats['numPeers'] ?? 0}'),
              const SizedBox(height: 8),
              _statRow('Seeds', '${stats['numSeeds'] ?? 0}'),
              if (_streamBufferInfo != null) ...[
                const SizedBox(height: 8),
                _statRow('Buffer',
                    '${(_streamBufferInfo!['bufferSeconds'] as double? ?? 0).toStringAsFixed(1)}s '
                    '(${_streamBufferInfo!['bufferPieces'] ?? 0}/${_streamBufferInfo!['readaheadWindow'] ?? 0} pieces)',
                    color: (_streamBufferInfo!['bufferPct'] as double? ?? 0) >= 0.5
                        ? Colors.green
                        : Colors.orange),
              ],
              const SizedBox(height: 8),
              _statRow('Progress',
                  '${((stats['progress'] as double? ?? 0) * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 8),
              _statRow('Downloaded',
                  _formatBytes(stats['totalDone'] ?? 0)),
              if (stats['totalWanted'] != null && (stats['totalWanted'] as int) > 0) ...[
                const SizedBox(height: 8),
                _statRow('Total Size',
                    _formatBytes(stats['totalWanted'] ?? 0)),
              ],
              const SizedBox(height: 8),
              _statRow('Source', widget.torrentStream!.source),
            ] else if (!isTorrent) ...[
              const SizedBox(height: 8),
              _statRow('Type', 'VOD Stream'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _errorWidget(BuildContext context) => Container(
    color: Colors.black87,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle, color: AppTheme.accent, size: 56),
          const SizedBox(height: 16),
          const Text('Failed to load stream.', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 24),
          TextButton(onPressed: _exitPlayer,
              child: const Text('Go Back', style: TextStyle(color: AppTheme.accent, fontSize: 16))),
        ],
      ),
    ),
  );

  Widget _buildControls(BuildContext context, String epName, bool hasEpisodes) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87],
          stops: const [0, 0.25, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Top bar
          Positioned(
            top: 32, left: 20, right: 20,
            child: Row(
              children: [
                HoverButton(
                  onTap: _exitPlayer,
                  backgroundColor: Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(epName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 16),
                // Network stats icon
                HoverButton(
                  onTap: () => setState(() {
                    _showStats = !_showStats;
                    _showSubtitles = false;
                    _showEpisodes = false;
                    _showAudioTracks = false;
                    _showSettings = false;
                  }),
                  backgroundColor: _showStats ? AppTheme.accent : Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(LucideIcons.wifi, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 16),
                HoverButton(
                  onTap: () => setState(() {
                    _showSettings = !_showSettings;
                    _showStats = false;
                    _showSubtitles = false;
                    _showEpisodes = false;
                    _showAudioTracks = false;
                  }),
                  backgroundColor: _showSettings ? AppTheme.accent : Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(LucideIcons.sliders, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 16),
                HoverButton(
                  onTap: () => setState(() {
                    _showSubtitles = !_showSubtitles;
                    _showEpisodes = false;
                    _showStats = false;
                    _showAudioTracks = false;
                    _showSettings = false;
                  }),
                  backgroundColor: _showSubtitles ? AppTheme.accent : Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: const Icon(LucideIcons.subtitles, color: Colors.white, size: 20),
                  ),
                ),
                if (_audioTracks.length > 1) ...[
                  const SizedBox(width: 16),
                  HoverButton(
                    onTap: () => setState(() {
                      _showAudioTracks = !_showAudioTracks;
                      _showSubtitles = false;
                      _showEpisodes = false;
                      _showStats = false;
                      _showSettings = false;
                    }),
                    backgroundColor: _showAudioTracks ? AppTheme.accent : Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: const Icon(LucideIcons.volume2, color: Colors.white, size: 20),
                    ),
                  ),
                ],
                if (hasEpisodes && widget.episodes.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  HoverButton(
                    onTap: () => setState(() {
                      _showEpisodes = !_showEpisodes;
                      _showSubtitles = false;
                      _showStats = false;
                      _showAudioTracks = false;
                      _showSettings = false;
                    }),
                    backgroundColor: _showEpisodes ? AppTheme.accent : Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: const Icon(LucideIcons.list, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Center play/pause (hidden during buffering)
          if (!_isTorrentBuffering && !_player.state.buffering)
            Center(
              child: StreamBuilder(
                stream: _player.stream.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? _player.state.playing;
                  return HoverButton(
                    onTap: () {
                      _player.playOrPause();
                      setState(() {});
                    },
                    backgroundColor: Colors.transparent,
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(_showControls ? 0.15 : 0.0),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Icon(
                            playing ? LucideIcons.pause : LucideIcons.play,
                            color: Colors.white.withOpacity(0.9),
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Episode navigation buttons (bottom left)
          if (hasEpisodes)
            Positioned(
              bottom: 16,
              left: 24,
              child: Row(
                children: [
                  HoverButton(
                    onTap: _currentEpIndex > 0
                        ? () => _playEpisode(_currentEpIndex - 1)
                        : () {},
                    backgroundColor: _currentEpIndex > 0
                        ? Colors.black54
                        : Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        LucideIcons.skipBack,
                        color: _currentEpIndex > 0
                            ? Colors.white
                            : Colors.white30,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  HoverButton(
                    onTap: _currentEpIndex < _effectiveEpisodeCount - 1
                        ? () => _playEpisode(_currentEpIndex + 1)
                        : () {},
                    backgroundColor:
                        _currentEpIndex < _effectiveEpisodeCount - 1
                            ? Colors.black54
                            : Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        LucideIcons.skipForward,
                        color: _currentEpIndex < _effectiveEpisodeCount - 1
                            ? Colors.white
                            : Colors.white30,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Fullscreen button (bottom right)
          Positioned(
            bottom: 16,
            right: 24,
            child: HoverButton(
              onTap: _toggleFullScreen,
              backgroundColor: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  _isFullScreen ? LucideIcons.minimize : LucideIcons.maximize,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          // Bottom progress + time
          Positioned(
            bottom: 52,
            left: 40,
            right: 40,
            child: StreamBuilder(
              stream: _player.stream.position,
              builder: (context, posSnap) => StreamBuilder(
                stream: _player.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final progress = dur.inMilliseconds > 0
                      ? pos.inMilliseconds / dur.inMilliseconds
                      : 0.0;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          Text(_fmt(dur),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbColor: AppTheme.accent,
                          activeTrackColor: AppTheme.accent,
                          inactiveTrackColor: Colors.white24,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: _isSeeking
                              ? _seekValue
                              : progress.clamp(0.0, 1.0),
                          onChangeStart: (v) {
                            _isSeeking = true;
                            _seekValue = v;
                          },
                          onChanged: (v) {
                            _seekValue = v;
                            setState(() {});
                          },
                          onChangeEnd: (v) {
                            _isSeeking = false;
                            if (dur != Duration.zero) {
                              final target = Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds).round());
                              _player.seek(target);
                              _startSeekRecovery(target);
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlePanel() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Subtitles',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
                if (!kIsWeb)
                  IconButton(
                    icon: const Icon(LucideIcons.upload, color: AppTheme.accent, size: 20),
                    tooltip: 'Import subtitle file',
                    onPressed: _importSubtitles,
                  ),
              ],
            ),
          ),
          if (_loadingSubs)
            const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accent)),
            )
          else if (_availableSubs.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No subtitles found',
                        style: TextStyle(color: AppTheme.textSecondary)),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _importSubtitles,
                        icon: const Icon(LucideIcons.upload, size: 16),
                        label: const Text('Import SRT / ZIP'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _availableSubs.length + 1,
                itemBuilder: (context, i) {
                    final sub = i > 0 ? _availableSubs[i - 1] : null;
                    return FocusableActionDetector(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (intent) {
                            if (i == 0) {
                              _player.setSubtitleTrack(SubtitleTrack.no());
                              setState(() {
                                _selectedSub = null;
                                _showSubtitles = false;
                              });
                            } else {
                              _selectSubtitle(_availableSubs[i - 1]);
                            }
                            return null;
                          },
                        ),
                      },
                      child: GestureDetector(
                        onTap: () {
                          if (i == 0) {
                            _player.setSubtitleTrack(SubtitleTrack.no());
                            setState(() {
                              _selectedSub = null;
                              _showSubtitles = false;
                            });
                          } else {
                            _selectSubtitle(_availableSubs[i - 1]);
                          }
                        },
                        child: _subtitleTile(
                          i == 0 ? 'Off' : '${sub!.language.toUpperCase()} - ${sub.fileName}',
                          i == 0 ? (_selectedSub == null) : (_selectedSub?.id == sub!.id),
                          subtitle: i == 0 ? null : sub!.matchType.label,
                          isLocal: sub?.source == 'local',
                          onDownloadSeason: (i > 0 && sub!.matchType == SubtitleMatchType.seasonFallback && sub.source != 'local' && !kIsWeb)
                              ? () => _downloadSeasonSubs(sub)
                              : null,
                        ),
                      ),
                    );
                },
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildColorButton(Color color, String name) {
    final active = _subColor.value == color.value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: HoverButton(
          onTap: () => _saveSubtitleColor(color),
          backgroundColor: active ? AppTheme.accent : Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              name,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double)? valueFormatter,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              valueFormatter != null ? valueFormatter(value) : value.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbColor: AppTheme.accent,
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: Colors.white12,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 50, 20, 8),
              child: Text(
                'Player Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  const SizedBox(height: 10),
                  const Text(
                    'INTRO SKIP',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  HoverButton(
                    onTap: () {
                      if (_introTimestamp != null) {
                        _resetIntro();
                      }
                    },
                    backgroundColor: _introTimestamp == null ? Colors.white10 : AppTheme.accent,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Text(
                        _introTimestamp == null ? 'No Intro Recorded' : 'Reset Intro Skip Time',
                        style: TextStyle(
                          color: _introTimestamp == null ? Colors.white38 : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSliderRow(
                    label: 'SUBTITLES FONT SIZE',
                    value: _subFontSize,
                    min: 12.0,
                    max: 60.0,
                    onChanged: _saveSubtitleFontSize,
                    valueFormatter: (v) => '${v.toInt()} px',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SUBTITLES COLOR',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildColorButton(Colors.white, 'White'),
                      _buildColorButton(Colors.yellow, 'Yellow'),
                      _buildColorButton(Colors.green, 'Green'),
                      _buildColorButton(Colors.cyan, 'Cyan'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSliderRow(
                    label: 'SUBTITLES POSITION (BOTTOM)',
                    value: _subPositionOffset,
                    min: 0.0,
                    max: 300.0,
                    onChanged: _saveSubtitlePosition,
                    valueFormatter: (v) => '${v.toInt()} px',
                  ),
                  const SizedBox(height: 16),
                  _buildSliderRow(
                    label: 'SUBTITLES HORIZ. PADDING',
                    value: _subHorizontalPadding,
                    min: 0.0,
                    max: 400.0,
                    onChanged: _saveSubtitleHorizontalPadding,
                    valueFormatter: (v) => '${v.toInt()} px',
                  ),
                  const SizedBox(height: 16),
                  _buildSliderRow(
                    label: 'SUBTITLES BG OPACITY',
                    value: _subBgOpacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: _saveSubtitleBgOpacity,
                    valueFormatter: (v) => '${(v * 100).round()}%',
                  ),
                  const Divider(color: Colors.white12, height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SUBTITLE COVER MASK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Switch(
                        value: _showSubMask,
                        activeColor: AppTheme.accent,
                        onChanged: _saveSubMaskEnabled,
                      ),
                    ],
                  ),
                  if (_showSubMask) ...[
                    const SizedBox(height: 16),
                    _buildSliderRow(
                      label: 'MASK WIDTH',
                      value: _subMaskWidthPct,
                      min: 0.1,
                      max: 1.0,
                      onChanged: _saveSubMaskWidthPct,
                      valueFormatter: (v) => '${(v * 100).round()}%',
                    ),
                    const SizedBox(height: 16),
                    _buildSliderRow(
                      label: 'MASK HEIGHT',
                      value: _subMaskHeight,
                      min: 10.0,
                      max: 200.0,
                      onChanged: _saveSubMaskHeight,
                      valueFormatter: (v) => '${v.toInt()} px',
                    ),
                    const SizedBox(height: 16),
                    _buildSliderRow(
                      label: 'MASK BOTTOM POSITION',
                      value: _subMaskPosition,
                      min: 0.0,
                      max: 300.0,
                      onChanged: _saveSubMaskPosition,
                      valueFormatter: (v) => '${v.toInt()} px',
                    ),
                    const SizedBox(height: 16),
                    _buildSliderRow(
                      label: 'MASK OPACITY',
                      value: _subMaskOpacity,
                      min: 0.0,
                      max: 1.0,
                      onChanged: _saveSubMaskOpacity,
                      valueFormatter: (v) => '${(v * 100).round()}%',
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTrackPanel() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 50, 20, 16),
              child: Text('Audio Tracks',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            if (_audioTracks.isEmpty)
              const Expanded(
                child: Center(
                    child: Text('No alternate audio tracks',
                        style: TextStyle(color: AppTheme.textSecondary))),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _audioTracks.length,
                  itemBuilder: (context, i) {
                    final track = _audioTracks[i];
                    final isActive = _selectedAudioTrack == track ||
                        (_selectedAudioTrack == null && i == 0);
                    final label = _audioTrackLabel(track);
                    return GestureDetector(
                      onTap: () => _selectAudioTrack(track),
                      child: _panelTile(label, isActive),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _audioTrackLabel(AudioTrack track) {
    final parts = <String>[];
    if (track.language != null && track.language!.isNotEmpty) {
      parts.add(track.language!.toUpperCase());
    }
    if (track.title != null && track.title!.isNotEmpty) {
      parts.add(track.title!);
    }
    if (track.codec != null && track.codec!.isNotEmpty) {
      parts.add(track.codec!.toUpperCase());
    }
    if (track.channels != null && track.channels!.isNotEmpty) {
      parts.add(track.channels!);
    }
    return parts.isNotEmpty ? parts.join(' - ') : 'Track ${track.id}';
  }

  Widget _panelTile(String title, bool isActive, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AppTheme.accent : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Icon(isActive ? LucideIcons.checkCircle : LucideIcons.circle,
              color: isActive ? AppTheme.accent : AppTheme.textSecondary,
              size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive ? Colors.white : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isActive ? AppTheme.accent : AppTheme.textSecondary.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitleTile(String title, bool isActive, {
    String? subtitle,
    bool isLocal = false,
    VoidCallback? onDownloadSeason,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AppTheme.accent : Colors.white24,
        ),
      ),
      child: Row(
        children: [
          Icon(isActive ? LucideIcons.checkCircle : LucideIcons.circle,
              color: isActive ? AppTheme.accent : AppTheme.textSecondary,
              size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isActive ? Colors.white : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLocal) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('LOCAL',
                            style: TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isActive ? AppTheme.accent : AppTheme.textSecondary.withOpacity(0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDownloadSeason != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDownloadSeason,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(LucideIcons.download, color: AppTheme.accent, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _downloadingSeason = false;

  Future<void> _downloadSeasonSubs(SubtitleItem item) async {
    if (_downloadingSeason) return;
    if (widget.tmdbId == null || widget.seasonNumber == null) return;

    setState(() => _downloadingSeason = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading season subtitles...'),
        duration: Duration(seconds: 3),
        backgroundColor: AppTheme.accent,
      ),
    );

    final saved = await SubtitleService.downloadSeasonSubtitles(
      item: item,
      tmdbId: widget.tmdbId!,
      season: widget.seasonNumber!,
    );

    if (mounted) {
      setState(() => _downloadingSeason = false);
      if (saved.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${saved.length} episode subtitle(s)'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.accent,
          ),
        );
        // Refresh subtitle list to include newly saved local files
        await _fetchSubtitles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No SRT files found in the download'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _importSubtitles() async {
    if (widget.tmdbId == null || widget.seasonNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subtitles can only be imported for TV show episodes'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'zip'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final saved = <SubtitleItem>[];
    for (final picked in result.files) {
      if (picked.path == null) continue;
      final path = picked.path!;
      final ext = path.split('.').last.toLowerCase();
      final file = File(path);
      final baseName = path.split(RegExp(r'[/\\]')).last;

      if (ext == 'zip') {
        final bytes = await file.readAsBytes();
        final batch = await SubtitleService.importLocalSubtitleBatch(
          zipBytes: bytes,
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
        );
        saved.addAll(batch);
      } else if (ext == 'srt') {
        final content = await file.readAsString();
        final item = await SubtitleService.importLocalSubtitle(
          fileName: baseName,
          content: content,
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
        );
        if (item != null) saved.add(item);
      }
    }

    if (mounted && saved.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${saved.length} subtitle(s)'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppTheme.accent,
        ),
      );
      await _fetchSubtitles();
    }
  }

  Widget _buildAutoplayCard() {
    final nextIdx = _currentEpIndex + 1;
    final nextEp = nextIdx < widget.episodes.length
        ? widget.episodes[nextIdx]
        : null;
    final nextTitle = nextEp?.name ?? 'Episode $nextIdx';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset((1 - value) * 120, 0),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () {}, // absorb taps
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 24),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  'Next Episode in ${_autoplayCountdown ~/ 60}:${(_autoplayCountdown % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Episode info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Episode thumbnail placeholder
                    Container(
                      width: 120,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          LucideIcons.play,
                          color: Colors.white54,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Episode details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    // Skip Later button — hide card, auto-skip when video ends
                    Expanded(
                      child: HoverButton(
                        onTap: () {
                          setState(() {
                            _showAutoplay = false;
                            _autoplayDismissed = true;
                          });
                        },
                        backgroundColor: Colors.white12,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.clock,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Skip Later',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Skip Now button
                    Expanded(
                      child: HoverButton(
                        onTap: _playNextEpisode,
                        backgroundColor: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.skipForward,
                                color: Colors.black,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Skip Now',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodePanel() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // absorb taps so they don't close the panel
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.95),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 50, 20, 16),
              child: Text('Episodes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.episodes.length,
                itemBuilder: (context, i) {
                  final ep = widget.episodes[i];
                  final isActive = i == _currentEpIndex;
                  return FocusableActionDetector(
                    actions: {
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (intent) {
                          _playEpisode(i);
                          return null;
                        },
                      ),
                    },
                    child: GestureDetector(
                      onTap: () => _playEpisode(i),
                      child: _panelTile(
                        ep.name.isNotEmpty ? ep.name : 'Episode ${i + 1}',
                        isActive,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
