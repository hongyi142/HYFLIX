import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/episode.dart';
import '../services/subtitle_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

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
  bool _hasError = false;
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

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _currentEpIndex = widget.initialEpisodeIndex;
    _currentTitle = widget.title;
    _player = Player();
    _controller = VideoController(_player);
    _openMedia(widget.videoUrl, seekToSeconds: widget.seekToSeconds);
    _loadIntroTimestamp();
    _listenPosition();
    _scheduleHideControls();
  }

  Future<void> _openMedia(String url, {int seekToSeconds = 0}) async {
    try {
      _bufferingSub?.cancel();
      await _player.open(Media(url));
      // Wait for the player to finish buffering before seeking
      if (seekToSeconds > 0) {
        bool hasSeeked = false;
        _bufferingSub = _player.stream.buffering.listen((buffering) {
          if (!buffering && !hasSeeked && mounted) {
            hasSeeked = true;
            _player.seek(Duration(seconds: seekToSeconds));
            _bufferingSub?.cancel();
          }
        });
        // Also try immediate seek in case player is already ready
        await _player.seek(Duration(seconds: seekToSeconds));
      }
      _fetchSubtitles();
    } catch (_) {
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

      if (_introTimestamp != null) {
        final skipDur = (_introTimestamp!['skipDuration'] as num?)?.toInt() ?? 
                        (_introTimestamp!['endSeconds'] as num?)?.toInt() ?? 0;
        shouldShow = sec < skipDur;
      } else {
        shouldShow = sec < 600; // Allow recording within first 10 mins
      }

      if (shouldShow != _showSkipIntro) {
        setState(() => _showSkipIntro = shouldShow);
      }
    });
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

  Future<void> _fetchSubtitles() async {
    if (mounted) setState(() => _loadingSubs = true);
    try {
      final currentEpisode = widget.episodes.isNotEmpty ? widget.episodes[_currentEpIndex] : null;
      final subs = await SubtitleService.searchSubtitles(
        _currentTitle ?? '',
        tmdbId: widget.tmdbId,
        seasonNumber: widget.seasonNumber,
        episodeName: currentEpisode?.name,
        isTvShow: widget.isTvShow,
      );
      if (mounted) {
        setState(() {
          _availableSubs = subs;
          _loadingSubs = false;
        });
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

    final srtContent = await SubtitleService.fetchSubtitleContent(item);

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
    if (index < 0 || index >= widget.episodes.length) return;
    final ep = widget.episodes[index];
    setState(() {
      _currentEpIndex = index;
      _hasError = false;
      _showEpisodes = false;
      _showSubtitles = false;
      _selectedSub = null;
      _availableSubs = [];
    });
    _openMedia(ep.url);
    _loadIntroTimestamp();
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
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _exitPlayer() async {
    await _saveWatchData();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveWatchData() async {
    if (AuthService.uid == null) return;
    final elapsed = _startTime != null ? DateTime.now().difference(_startTime!).inSeconds : 0;
    if (elapsed > 5) {
      UserService.addWatchTime(elapsed);
    }
    // Capture player state before disposal
    final position = _player.state.position;
    final duration = _player.state.duration;
    final progress = duration.inSeconds > 0
        ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    final currentEp = widget.episodes.isNotEmpty ? widget.episodes[_currentEpIndex] : null;
    if (currentEp != null || widget.videoUrl.isNotEmpty) {
      await UserService.saveWatchHistory(
        contentId: widget.tmdbId ?? widget.title,
        title: widget.title,
        posterUrl: widget.posterUrl,
        progress: progress,
        originalTitle: widget.originalTitle,
        episodeIndex: _currentEpIndex,
        positionSeconds: position.inSeconds,
      );
    }
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
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) _exitPlayer();
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) _player.playOrPause();
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyS && _showSkipIntro) {
          if (_introTimestamp == null) _recordIntro();
          else _skipIntro();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            if (_showSubtitles || _showEpisodes) {
              setState(() { _showSubtitles = false; _showEpisodes = false; });
            } else {
              _toggleControls();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _controller,
                controls: NoVideoControls,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    backgroundColor: Color(0xDD000000),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),

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

              // Skip Intro / Record Intro button
              Positioned(
                bottom: 100,
                left: 24,
                child: AnimatedOpacity(
                  opacity: _showSkipIntro ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: _showSkipIntro
                      ? GestureDetector(
                          onTap: _introTimestamp == null ? _recordIntro : _skipIntro,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
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

              // Subtitle panel (slides from right)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                top: 0, bottom: 0,
                right: _showSubtitles ? 0 : -300,
                width: 300,
                child: _buildSubtitlePanel(),
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
                GestureDetector(
                  onTap: _exitPlayer,
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
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => setState(() {
                    _showSubtitles = !_showSubtitles;
                    _showEpisodes = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _showSubtitles ? AppTheme.accent : Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(LucideIcons.subtitles, color: Colors.white, size: 20),
                  ),
                ),
                if (hasEpisodes) ...[
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() {
                      _showEpisodes = !_showEpisodes;
                      _showSubtitles = false;
                    }),
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
                  onTap: () {
                    _player.playOrPause();
                    setState(() {});
                  },
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

          // Bottom progress + time
          Positioned(
            bottom: 32,
            left: 32,
            right: 32,
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
                          value: progress.clamp(0.0, 1.0),
                          onChanged: (v) {
                            if (dur != Duration.zero) {
                              _player.seek(Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds).round()));
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

  Widget _buildSubtitlePanel() {
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
            child: Text('Subtitles',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          if (_loadingSubs)
            const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accent)),
            )
          else if (_availableSubs.isEmpty)
            const Expanded(
              child: Center(
                  child: Text('No subtitles found',
                      style: TextStyle(color: AppTheme.textSecondary))),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _availableSubs.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // Off option
                    final isActive = _selectedSub == null;
                    return GestureDetector(
                      onTap: () {
                        _player.setSubtitleTrack(SubtitleTrack.no());
                        setState(() {
                          _selectedSub = null;
                          _showSubtitles = false;
                        });
                      },
                      child: _panelTile('Off', isActive),
                    );
                  }

                  final sub = _availableSubs[i - 1];
                  final isActive = _selectedSub?.id == sub.id;
                  return GestureDetector(
                    onTap: () => _selectSubtitle(sub),
                    child: _panelTile(
                      '${sub.language.toUpperCase()} - ${sub.fileName}',
                      isActive,
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

  Widget _panelTile(String title, bool isActive) {
    return Container(
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
          Icon(isActive ? LucideIcons.checkCircle : LucideIcons.circle,
              color: isActive ? AppTheme.accent : AppTheme.textSecondary,
              size: 16),
          const SizedBox(width: 10),
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
        ],
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
                  return GestureDetector(
                    onTap: () => _playEpisode(i),
                    child: _panelTile(
                      ep.name.isNotEmpty ? ep.name : 'Episode ${i + 1}',
                      isActive,
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
