import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../core/proxy_url.dart';
import '../models/episode.dart';
import '../models/torrent_stream.dart';
import '../widgets/buttons.dart';
import 'fullscreen_web.dart';

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
    // ignore: undefined_prefixed_name
    html.platformViewRegistry
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

    if (isHls && hlsClass != null && hlsClass['isSupported']()) {
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
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video
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
              ],
            ),
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
                    if (hasEpisodes)
                      HoverButton(
                        onTap: () =>
                            setState(() => _showEpisodes = !_showEpisodes),
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
                    const Spacer(),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
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
}
