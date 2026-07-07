import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme.dart';
import '../core/proxy_url.dart';
import '../models/episode.dart';
import '../models/torrent_stream.dart';
import '../widgets/buttons.dart';
import 'fullscreen_web.dart';
import '../services/subtitle_service.dart';

/// Lightweight web video controller using an HTML <video> element + hls.js.
class _WebVideoController {
  html.VideoElement? _video;
  js.JsObject? _hls;
  String? _viewType;
  bool _isInitialized = false;
  bool _hasError = false;

  bool get isInitialized => _isInitialized;
  bool get hasError => _hasError;
  html.VideoElement? get video => _video;
  String? get viewType => _viewType;

  // Value notifiers for UI updates
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<double> aspectRatio = ValueNotifier(16 / 9);

  Timer? _pollTimer;

  Future<void> initialize(String url) async {
    _disposeHls();
    _isInitialized = false;
    _hasError = false;

    // Create a unique view type for this player instance
    _viewType = 'hyflix-video-${DateTime.now().microsecondsSinceEpoch}';
    _video = html.VideoElement()
      ..id = _viewType!
      ..setAttribute('style', 'width:100%;height:100%;object-fit:contain;background:#000')
      ..preload = 'auto'
      ..crossOrigin = 'anonymous';

    // Register the video element as a platform view
    ui_web.platformViewRegistry
        .registerViewFactory(_viewType!, (int viewId) => _video!);

    // Listen for native events
    _video!.onPlay.listen((_) => isPlaying.value = true);
    _video!.onPause.listen((_) => isPlaying.value = false);
    _video!.onPlaying.listen((_) {
      isBuffering.value = false;
      isPlaying.value = true;
    });
    _video!.onWaiting.listen((_) => isBuffering.value = true);
    _video!.onError.listen((_) {
      _hasError = true;
      isBuffering.value = false;
    });
    _video!.onEnded.listen((_) => isPlaying.value = false);

    _video!.onLoadedMetadata.listen((_) {
      _isInitialized = true;
      final w = _video!.videoWidth;
      final h = _video!.videoHeight;
      if (w > 0 && h > 0) {
        aspectRatio.value = w / h;
      }
      final dur = _video!.duration;
      if (dur.isFinite && dur > 0) {
        duration.value = Duration(milliseconds: (dur * 1000).round());
      }
    });

    // Poll position every 200ms
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_video == null) return;
      position.value = Duration(
          milliseconds: (_video!.currentTime * 1000).round());
      final dur = _video!.duration;
      if (dur.isFinite && dur > 0) {
        duration.value = Duration(milliseconds: (dur * 1000).round());
      }
    });

    // Determine playback method
    final isHls = url.contains('.m3u8');
    final hlsClass = js.context['Hls'];

    if (isHls && hlsClass != null && hlsClass.callMethod('isSupported') == true) {
      // Use hls.js for m3u8 streams on non-Safari browsers
      _hls = js.JsObject(hlsClass);
      _hls!.callMethod('loadSource', [url]);
      _hls!.callMethod('attachMedia', [_video]);
    } else if (isHls && _video!.canPlayType('application/vnd.apple.mpegurl') != '') {
      // Safari native HLS
      _video!.src = url;
    } else {
      // mp4 or other native formats
      _video!.src = url;
    }
  }

  void play() => _video?.play();
  void pause() => _video?.pause();

  void playOrPause() {
    if (_video == null) return;
    if (_video!.paused) {
      _video!.play();
    } else {
      _video!.pause();
    }
  }

  void seekTo(Duration position) {
    _video?.currentTime = position.inMilliseconds / 1000.0;
  }

  void setPlaybackSpeed(double speed) {
    if (_video != null) _video!.playbackRate = speed;
  }

  void setVolume(double volume) {
    if (_video != null) _video!.volume = volume.clamp(0.0, 1.0);
  }

  String srtToVtt(String srtContent) {
    var vtt = srtContent.replaceAllMapped(
      RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
      (Match m) => '${m.group(1)}.${m.group(2)}',
    );
    if (!vtt.startsWith('WEBVTT')) {
      vtt = 'WEBVTT\n\n$vtt';
    }
    return vtt;
  }

  void setSubtitleTrack(String? srtContent, {String title = 'Subtitles', String language = 'en'}) {
    if (_video == null) return;
    _video!.querySelectorAll('track').forEach((el) => el.remove());

    if (srtContent == null || srtContent.trim().isEmpty) return;

    final vttContent = srtToVtt(srtContent);
    final blob = html.Blob([vttContent], 'text/vtt');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    final track = html.TrackElement()
      ..src = url
      ..kind = 'subtitles'
      ..srclang = language
      ..label = title
      ..setAttribute('default', 'true');
      
    _video!.append(track);
    debugPrint('[VideoPlayer:Web] Set subtitle track: $title ($language)');
  }

  void _disposeHls() {
    if (_hls != null) {
      try {
        _hls!.callMethod('destroy');
      } catch (_) {}
      _hls = null;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _disposeHls();
    _video?.pause();
    _video?.removeAttribute('src');
    _video?.load();
    _video = null;
    _isInitialized = false;
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String originalTitle;
  final List<Episode> episodes;
  final int initialEpisodeIndex;
  final String? tmdbId;
  final bool isTvShow;
  final int? seasonNumber;
  final String posterUrl;
  final int seekToSeconds;
  final TorrentStream? torrentStream;
  final int? episodeNumber;
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
    this.posterUrl = '',
    this.seekToSeconds = 0,
    this.torrentStream,
    this.episodeNumber,
    this.episodeCount = 0,
    this.videoSourceName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  _WebVideoController? _controller;
  bool _showControls = true;
  bool _showEpisodes = false;
  bool _hasError = false;
  bool _isInitialized = false;
  late int _currentEpIndex;
  String? _currentUrl;
  Timer? _hideControlsTimer;
  bool _isExiting = false;
  bool _isFullScreen = false;
  bool _isLongPressSpeed = false;

  // Scrubbing state
  bool _isSeeking = false;
  double _seekValue = 0.0;

  // Listeners
  VoidCallback? _posListener;
  VoidCallback? _durListener;
  VoidCallback? _playListener;
  VoidCallback? _bufListener;
  VoidCallback? _arListener;

  @override
  void initState() {
    super.initState();
    _currentEpIndex = widget.initialEpisodeIndex;
    _currentUrl = widget.videoUrl;
    _initPlayer(_currentUrl!);
  }

  bool _needsResolving(String url) {
    if (url.toLowerCase().contains('.m3u8')) return false;
    if (url.toLowerCase().contains('.mp4')) return false;
    if (url.contains('/share/') || url.contains('index.php?url=')) return true;
    return false;
  }

  Future<String> _resolveUrlIfNeeded(String url) async {
    if (!_needsResolving(url)) return url;

    try {
      final encoded = Uri.encodeComponent(url);
      final proxyRequestUrl = '/api/proxy?resolve=true&url=$encoded';
      debugPrint('[VideoPlayer:Web] Resolving share URL: $url');
      final response = await http.get(Uri.parse(proxyRequestUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data.containsKey('url') && data['url'] is String) {
          final resolvedUrl = data['url'] as String;
          debugPrint('[VideoPlayer:Web] Resolved: $url -> $resolvedUrl');
          return resolvedUrl;
        }
      }
      debugPrint('[VideoPlayer:Web] Failed to resolve: ${response.statusCode}');
    } catch (e) {
      debugPrint('[VideoPlayer:Web] Resolve error: $e');
    }
    return url;
  }

  Future<void> _initPlayer(String url) async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      final resolvedUrl = await _resolveUrlIfNeeded(url);

      // Dispose previous controller
      _removeListeners();
      _controller?.dispose();

      final ctrl = _WebVideoController();
      _controller = ctrl;

      // Attach listeners before initialize to catch all events
      _posListener = () {
        if (mounted) setState(() {});
      };
      _durListener = () {
        if (mounted) setState(() {});
      };
      _playListener = () {
        if (mounted) setState(() {});
      };
      _bufListener = () {
        if (mounted) setState(() {});
      };
      _arListener = () {
        if (mounted) setState(() {});
      };

      ctrl.position.addListener(_posListener!);
      ctrl.duration.addListener(_durListener!);
      ctrl.isPlaying.addListener(_playListener!);
      ctrl.isBuffering.addListener(_bufListener!);
      ctrl.aspectRatio.addListener(_arListener!);

      await ctrl.initialize(proxyUrl(resolvedUrl));

      if (!mounted) {
        ctrl.dispose();
        return;
      }

      if (ctrl.hasError) {
        setState(() => _hasError = true);
        return;
      }

      setState(() => _isInitialized = true);

      // Seek if resuming
      if (widget.seekToSeconds > 0) {
        ctrl.seekTo(Duration(seconds: widget.seekToSeconds));
      }
      ctrl.play();
      _scheduleHideControls();
      _fetchSubtitles();
    } catch (e) {
      debugPrint('[VideoPlayer:Web] Init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _removeListeners() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (_posListener != null) ctrl.position.removeListener(_posListener!);
    if (_durListener != null) ctrl.duration.removeListener(_durListener!);
    if (_playListener != null) ctrl.isPlaying.removeListener(_playListener!);
    if (_bufListener != null) ctrl.isBuffering.removeListener(_bufListener!);
    if (_arListener != null) ctrl.aspectRatio.removeListener(_arListener!);
    _posListener = null;
    _durListener = null;
    _playListener = null;
    _bufListener = null;
    _arListener = null;
  }

  void _playEpisode(int index) {
    if (index < 0 || index >= widget.episodes.length) return;
    setState(() {
      _currentEpIndex = index;
      _showEpisodes = false;
      _showSubtitles = false;
      _selectedSub = null;
      _availableSubs = [];
    });
    _initPlayer(widget.episodes[index].url);
  }

  void _togglePlayPause() {
    _controller?.playOrPause();
    _scheduleHideControls();
  }

  void _seekRelative(int seconds) {
    final ctrl = _controller;
    if (ctrl == null || !_isInitialized) return;
    final pos = ctrl.position.value;
    final dur = ctrl.duration.value;
    final target = pos + Duration(seconds: seconds);
    final clamped = target.isNegative ? Duration.zero : (target > dur ? dur : target);
    ctrl.seekTo(clamped);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller?.isPlaying.value == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    try {
      toggleFullScreen();
    } catch (e) {
      debugPrint('[VideoPlayer:Web] Fullscreen toggle error: $e');
      if (mounted) setState(() => _isFullScreen = !_isFullScreen);
    }
  }

  Future<void> _exitPlayer() async {
    if (_isExiting) return;
    _isExiting = true;
    _hideControlsTimer?.cancel();
    _removeListeners();
    _controller?.dispose();
    _controller = null;
    if (mounted) Navigator.pop(context);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _removeListeners();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasEpisodes = widget.episodes.length > 1;
    final currentEpName = hasEpisodes
        ? widget.episodes[_currentEpIndex].name
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
          if (e is KeyDownEvent) {
            if (e.logicalKey == LogicalKeyboardKey.escape) _exitPlayer();
            if (e.logicalKey == LogicalKeyboardKey.space) _togglePlayPause();
            if (e.logicalKey == LogicalKeyboardKey.arrowLeft) _seekRelative(-10);
            if (e.logicalKey == LogicalKeyboardKey.arrowRight) _seekRelative(10);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Video / Error / Loading States
              if (_isInitialized &&
                  _controller != null &&
                  _controller!.viewType != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.aspectRatio.value,
                    child: HtmlElementView(
                      viewType: _controller!.viewType!,
                    ),
                  ),
                )
              else if (_hasError)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 48),
                      SizedBox(height: 16),
                      Text('Failed to load video',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                )
              else
                const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.accent),
                ),

              // Transparent gesture overlay to intercept pointer events from HtmlElementView on Web
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onLongPressStart: (_) {
                    if (!_isLongPressSpeed && _isInitialized) {
                      setState(() => _isLongPressSpeed = true);
                      _controller?.setPlaybackSpeed(2.0);
                    }
                  },
                  onLongPressEnd: (_) {
                    if (_isLongPressSpeed) {
                      setState(() => _isLongPressSpeed = false);
                      _controller?.setPlaybackSpeed(1.0);
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),

                // Buffering indicator
                if (_isInitialized &&
                    _controller != null &&
                    _controller!.isBuffering.value)
                  const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.accent, strokeWidth: 3),
                  ),

                // Long-press speed indicator
                if (_isLongPressSpeed)
                  Positioned(
                    top: 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, color: Colors.amber, size: 18),
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
                    child: _buildControls(currentEpName, hasEpisodes),
                  ),
                ),

                // Episode panel
                if (_showEpisodes && hasEpisodes)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 300,
                    child: _buildEpisodePanel(),
                  ),

                // Subtitle panel
                if (_showSubtitles)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 300,
                    child: _buildSubtitlePanel(),
                  ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildControls(String epName, bool hasEpisodes) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
            Colors.transparent,
            Colors.black54
          ],
          stops: [0.0, 0.2, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    HoverButton(
                      onTap: _exitPlayer,
                      backgroundColor: Colors.black45,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        epName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.tmdbId != null) ...[
                      HoverButton(
                        onTap: () => setState(() {
                          _showSubtitles = !_showSubtitles;
                          _showEpisodes = false;
                        }),
                        backgroundColor:
                            _showSubtitles ? AppTheme.accent : Colors.black45,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(LucideIcons.subtitles,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (hasEpisodes)
                      HoverButton(
                        onTap: () =>
                            setState(() {
                              _showEpisodes = !_showEpisodes;
                              _showSubtitles = false;
                            }),
                        backgroundColor:
                            _showEpisodes ? AppTheme.accent : Colors.black45,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(LucideIcons.list,
                              color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Center play/pause
          if (_isInitialized)
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HoverButton(
                    onTap: () => _seekRelative(-10),
                    backgroundColor: Colors.black45,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.replay_10,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(width: 24),
                  HoverButton(
                    onTap: _togglePlayPause,
                    backgroundColor: Colors.black45,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        _controller?.isPlaying.value == true
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  HoverButton(
                    onTap: () => _seekRelative(10),
                    backgroundColor: Colors.black45,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.forward_10,
                          color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom progress bar + fullscreen
          if (_isInitialized && _controller != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildProgressBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final position = _controller!.position.value;
    final duration = _controller!.duration.value;
    final progress =
        duration.inSeconds > 0 ? position.inSeconds / duration.inSeconds : 0.0;

    return GestureDetector(
      onTap: () {}, // Prevent toggle controls
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: AppTheme.accent,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: _isSeeking
                      ? _seekValue
                      : progress.clamp(0.0, 1.0),
                  min: 0,
                  max: 1.0,
                  onChangeStart: (v) {
                    _isSeeking = true;
                    _seekValue = v;
                    _hideControlsTimer?.cancel();
                  },
                  onChanged: (v) {
                    _seekValue = v;
                    setState(() {});
                  },
                  onChangeEnd: (v) {
                    _isSeeking = false;
                    if (duration.inSeconds > 0) {
                      final target = Duration(
                          milliseconds:
                              (v * duration.inMilliseconds).round());
                      _controller!.seekTo(target);
                    }
                    _scheduleHideControls();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    HoverButton(
                      onTap: _toggleFullScreen,
                      backgroundColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _isFullScreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white70,
                          size: 22,
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
    return Container(
      color: AppTheme.surface.withOpacity(0.95),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Episodes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  HoverButton(
                    onTap: () =>
                        setState(() => _showEpisodes = false),
                    backgroundColor: Colors.white12,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child:
                          Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.episodes.length,
              itemBuilder: (context, i) {
                final ep = widget.episodes[i];
                final isCurrent = i == _currentEpIndex;
                return InkWell(
                  onTap: () => _playEpisode(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color:
                        isCurrent ? AppTheme.accent.withOpacity(0.15) : null,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: isCurrent
                                  ? AppTheme.accent
                                  : Colors.white54,
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            ep.name,
                            style: TextStyle(
                              color:
                                  isCurrent ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent)
                          const Icon(Icons.play_circle_filled,
                              color: AppTheme.accent, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _showSubtitles = false;
  bool _loadingSubs = false;
  List<SubtitleItem> _availableSubs = [];
  SubtitleItem? _selectedSub;
  bool _downloadingSeason = false;
  int _subDelayOffsetMs = 0;
  String? _loadedSrtContent;

  Future<void> _fetchSubtitles() async {
    if (mounted) setState(() => _loadingSubs = true);
    try {
      final currentEpisode = widget.episodes.isNotEmpty ? widget.episodes[_currentEpIndex] : null;
      final epNum = widget.episodeNumber ?? (widget.episodes.isNotEmpty ? _currentEpIndex + 1 : null);
      final subs = await SubtitleService.searchSubtitles(
        widget.originalTitle.isNotEmpty ? widget.originalTitle : widget.title,
        tmdbId: widget.tmdbId,
        seasonNumber: widget.seasonNumber,
        episodeNumber: epNum,
        episodeName: currentEpisode?.name,
        isTvShow: widget.isTvShow,
      );

      // Load locally stored subtitles
      List<SubtitleItem> localSubs = [];
      if (widget.tmdbId != null && widget.seasonNumber != null) {
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
    } catch (e) {
      debugPrint('[VideoPlayer:Web] Error fetching subtitles: $e');
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
    final epNum = widget.episodeNumber ?? (widget.episodes.isNotEmpty ? _currentEpIndex + 1 : null);
    
    if (item.source == 'local' && item.localPath != null) {
      srtContent = await SubtitleService.readLocalSubtitle(
        item.localPath!,
        episodeNumber: item.matchType == SubtitleMatchType.seasonFallback ? epNum : null,
      );
    } else if (item.matchType == SubtitleMatchType.seasonFallback && epNum != null && widget.tmdbId != null && widget.seasonNumber != null) {
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
        await _fetchSubtitles();
        
        final matchingLocal = await SubtitleService.findMatchingLocalSubtitle(
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
          episodeNumber: epNum,
        );
        
        if (matchingLocal != null) {
          _selectedSub = matchingLocal;
          srtContent = await SubtitleService.readLocalSubtitle(
            matchingLocal.localPath!,
          );
        } else {
          srtContent = await SubtitleService.readLocalSubtitle(
            saved.first.localPath!,
            episodeNumber: epNum,
          );
        }
      } else {
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

    if (srtContent != null && srtContent.trim().isNotEmpty) {
      setState(() {
        _subDelayOffsetMs = 0;
        _loadedSrtContent = srtContent;
      });

      _controller?.setSubtitleTrack(
        srtContent,
        title: item.fileName,
        language: item.language,
      );

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
      if (picked.bytes == null) continue;
      final name = picked.name;
      final ext = name.split('.').last.toLowerCase();

      if (ext == 'zip') {
        final batch = await SubtitleService.importLocalSubtitleBatch(
          zipBytes: picked.bytes!,
          tmdbId: widget.tmdbId!,
          season: widget.seasonNumber!,
        );
        saved.addAll(batch);
      } else if (ext == 'srt') {
        final content = utf8.decode(picked.bytes!, allowMalformed: true);
        final item = await SubtitleService.importLocalSubtitle(
          fileName: name,
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
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _importSubtitles,
                        icon: const Icon(LucideIcons.upload, size: 16),
                        label: const Text('Import SRT / ZIP'),
                      ),
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
                    return GestureDetector(
                      onTap: () {
                        if (i == 0) {
                          _controller?.setSubtitleTrack(null);
                          setState(() {
                            _selectedSub = null;
                            _subDelayOffsetMs = 0;
                            _loadedSrtContent = null;
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
                        onDownloadSeason: (i > 0 && sub!.matchType == SubtitleMatchType.seasonFallback && sub.source != 'local')
                            ? () => _downloadSeasonSubs(sub)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            if (_selectedSub != null) ...[
              const Divider(color: Colors.white24, height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Subtitle Sync Offset',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(_subDelayOffsetMs / 1000.0).toStringAsFixed(1)}s',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            _delayButton(
                              label: '-0.5s',
                              onTap: () => _adjustSubtitleDelay(-500),
                            ),
                            const SizedBox(width: 8),
                            _delayButton(
                              label: 'Reset',
                              onTap: () => _adjustSubtitleDelay(0, isReset: true),
                            ),
                            const SizedBox(width: 8),
                            _delayButton(
                              label: '+0.5s',
                              onTap: () => _adjustSubtitleDelay(500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _adjustSubtitleDelay(int ms, {bool isReset = false}) {
    if (_selectedSub == null || _loadedSrtContent == null) return;
    setState(() {
      if (isReset) {
        _subDelayOffsetMs = 0;
      } else {
        _subDelayOffsetMs += ms;
      }
    });

    final shifted = _shiftSrtTimestamps(
      _loadedSrtContent!,
      Duration(milliseconds: _subDelayOffsetMs),
    );
    _controller?.setSubtitleTrack(
      shifted,
      title: _selectedSub!.fileName,
      language: _selectedSub!.language,
    );
  }

  Widget _delayButton({required String label, required VoidCallback onTap}) {
    return HoverButton(
      onTap: onTap,
      backgroundColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  static Duration _parseSrtTime(String h, String m, String s, String ms) {
    return Duration(
      hours: int.parse(h),
      minutes: int.parse(m),
      seconds: int.parse(s),
      milliseconds: int.parse(ms),
    );
  }

  static String _formatSrtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  String _shiftSrtTimestamps(String srtContent, Duration shift) {
    if (shift == Duration.zero) return srtContent;
    return srtContent.replaceAllMapped(
      RegExp(r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})'),
      (Match m) {
        final original = _parseSrtTime(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
        final shifted = original + shift;
        final finalDuration = shifted.isNegative ? Duration.zero : shifted;
        return _formatSrtTime(finalDuration);
      },
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
}
