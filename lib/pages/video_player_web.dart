import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../core/proxy_url.dart';
import '../models/episode.dart';
import '../models/torrent_stream.dart';
import '../widgets/buttons.dart';
import 'fullscreen_web.dart';

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
  VideoPlayerController? _controller;
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

  @override
  void initState() {
    super.initState();
    _currentEpIndex = widget.initialEpisodeIndex;
    _currentUrl = widget.videoUrl;
    _initPlayer(_currentUrl!);
  }

  Future<void> _initPlayer(String url) async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      _controller?.dispose();
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(proxyUrl(url)),
        httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
      );
      _controller = controller;

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() => _isInitialized = true);

      controller.addListener(_onPlayerUpdate);

      if (widget.seekToSeconds > 0) {
        await controller.seekTo(Duration(seconds: widget.seekToSeconds));
      }
      await controller.play();
      _scheduleHideControls();
    } catch (e) {
      debugPrint('[VideoPlayer:Web] Init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;

    // Auto-advance to next episode on completion
    if (value.position >= value.duration &&
        value.duration.inSeconds > 0 &&
        !_isAtLastEpisode()) {
      _playNextEpisode();
    }

    // Update UI
    setState(() {});
  }

  bool _isAtLastEpisode() =>
      widget.episodes.isEmpty || _currentEpIndex >= widget.episodes.length - 1;

  void _playNextEpisode() {
    if (_isAtLastEpisode()) return;
    _playEpisode(_currentEpIndex + 1);
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
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _scheduleHideControls();
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_isInitialized) return;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final target = pos + Duration(seconds: seconds);
    final clamped = target.isNegative ? Duration.zero : (target > dur ? dur : target);
    _controller!.seekTo(clamped);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller?.value.isPlaying == true) {
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
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
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
              // Video
              if (_isInitialized && _controller != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
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
                          style: TextStyle(color: Colors.white70, fontSize: 16)),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),

              // Buffering indicator
              if (_isInitialized &&
                  _controller != null &&
                  _controller!.value.isBuffering)
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 3),
                ),

              // Tap catcher — above video so taps are caught before the
              // HTML <video> element consumes them.
              GestureDetector(
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
                child: const SizedBox.expand(),
              ),

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
    );
  }

  Widget _buildControls(String epName, bool hasEpisodes) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    HoverButton(
                      onTap: _exitPlayer,
                      backgroundColor: Colors.black45,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
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
                        onTap: () => setState(() {
                          _showEpisodes = !_showEpisodes;
                        }),
                        backgroundColor: _showEpisodes
                            ? AppTheme.accent
                            : Colors.black45,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(LucideIcons.list, color: Colors.white, size: 20),
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
                      child: Icon(Icons.replay_10, color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(width: 24),
                  HoverButton(
                    onTap: _togglePlayPause,
                    backgroundColor: Colors.black45,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        _controller?.value.isPlaying == true
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
                      child: Icon(Icons.forward_10, color: Colors.white, size: 32),
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
    final value = _controller!.value;
    final position = value.position;
    final duration = value.duration;

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
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: duration.inSeconds > 0
                      ? position.inSeconds.toDouble().clamp(0.0, duration.inSeconds.toDouble())
                      : 0.0,
                  min: 0,
                  max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                  onChanged: (v) {
                    _controller!.seekTo(Duration(seconds: v.toInt()));
                  },
                  onChangeStart: (_) {
                    _hideControlsTimer?.cancel();
                  },
                  onChangeEnd: (_) {
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    HoverButton(
                      onTap: _toggleFullScreen,
                      backgroundColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          color: Colors.white70,
                          size: 22,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    onTap: () => setState(() => _showEpisodes = false),
                    backgroundColor: Colors.white12,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, color: Colors.white, size: 18),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: isCurrent ? AppTheme.accent.withOpacity(0.15) : null,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: isCurrent ? AppTheme.accent : Colors.white54,
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            ep.name,
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
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
