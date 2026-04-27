import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/episode.dart';
import '../services/subtitle_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final List<Episode> episodes;
  final int initialEpisodeIndex;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.episodes = const [],
    this.initialEpisodeIndex = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  bool _showEpisodes = false;
  bool _hasError = false;
  late int _currentEpIndex;
  String? _currentTitle;

  @override
  void initState() {
    super.initState();
    _currentEpIndex = widget.initialEpisodeIndex;
    _currentTitle = widget.title;
    _player = Player();
    _controller = VideoController(_player);
    _openMedia(widget.videoUrl);
    _scheduleHideControls();
  }

  Future<void> _openMedia(String url) async {
    try {
      await _player.open(Media(url));
      _tryLoadSubtitles();
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _tryLoadSubtitles() async {
    final searchTitle = _currentTitle ?? widget.title;
    final url = await SubtitleService.getSubtitleUrl(searchTitle);
    if (url != null && mounted) {
      await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: 'English', language: 'en'));
    }
  }

  void _playEpisode(int index) {
    if (index < 0 || index >= widget.episodes.length) return;
    final ep = widget.episodes[index];
    setState(() {
      _currentEpIndex = index;
      _hasError = false;
      _showEpisodes = false;
    });
    _openMedia(ep.url);
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
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasEpisodes = widget.episodes.length > 1;
    final currentEpName = hasEpisodes
        ? widget.episodes[_currentEpIndex].name
        : widget.title;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) Navigator.pop(context);
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) _player.playOrPause();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _controller),

              // Error state
              if (_hasError)
                _errorWidget(context),

              // Controls overlay
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildControls(context, currentEpName, hasEpisodes),
                ),
              ),

              // Episode panel (slides from right)
              if (hasEpisodes)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: 0, bottom: 0,
                  right: _showEpisodes ? 0 : -300,
                  width: 300,
                  child: _buildEpisodePanel(),
                ),
            ],
          ),
        ),
      ),
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
          TextButton(onPressed: () => Navigator.pop(context),
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
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(epName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (hasEpisodes)
                  GestureDetector(
                    onTap: () => setState(() => _showEpisodes = !_showEpisodes),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _showEpisodes ? AppTheme.accent : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(LucideIcons.list, color: Colors.white, size: 20),
                    ),
                  ),
              ],
            ),
          ),

          // Center play/pause
          Center(
            child: StreamBuilder(
              stream: _player.stream.playing,
              builder: (context, snap) {
                final playing = snap.data ?? false;
                return GestureDetector(
                  onTap: () { _player.playOrPause(); setState(() {}); },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.4), blurRadius: 30, spreadRadius: 4)],
                    ),
                    child: Icon(playing ? LucideIcons.pause : LucideIcons.play, color: Colors.white, size: 42),
                  ),
                );
              },
            ),
          ),

          // Bottom progress + time
          Positioned(
            bottom: 32, left: 32, right: 32,
            child: StreamBuilder(
              stream: _player.stream.position,
              builder: (context, posSnap) => StreamBuilder(
                stream: _player.stream.duration,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final progress = dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbColor: AppTheme.accent,
                          activeTrackColor: AppTheme.accent,
                          inactiveTrackColor: Colors.white24,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: progress.clamp(0.0, 1.0),
                          onChanged: (v) {
                            if (dur != Duration.zero) {
                              _player.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
                            }
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

  Widget _buildEpisodePanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.95),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 50, 20, 16),
            child: Text('Episodes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.episodes.length,
              itemBuilder: (context, i) {
                final ep = widget.episodes[i];
                final isActive = i == _currentEpIndex;
                return GestureDetector(
                  onTap: () => _playEpisode(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.accent.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive ? AppTheme.accent : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(isActive ? LucideIcons.playCircle : LucideIcons.circle,
                            color: isActive ? AppTheme.accent : AppTheme.textSecondary, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ep.name.isNotEmpty ? ep.name : 'Episode ${i + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : AppTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
