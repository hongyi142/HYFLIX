import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lucide_icons/lucide_icons.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../pages/video_player_screen.dart';
import '../services/tmdb_service.dart';
import '../services/torrent_service.dart';
import '../services/video_preview.dart';
import 'video_preview_widget.dart';

class VideoCard extends StatefulWidget {
  final ContentModel content;
  final VoidCallback? onWatchHistoryChanged;
  final double width;
  final EdgeInsetsGeometry margin;
  /// Custom resume handler for Continue Watching cards.
  /// When set, tapping a card with resume data calls this instead of the
  /// default built-in resume logic. Arguments: episodeIndex, seekToSeconds.
  final Future<void> Function(int episodeIndex, int seekToSeconds)? onResumeTap;

  const VideoCard({
    super.key,
    required this.content,
    this.onWatchHistoryChanged,
    this.width = 280,
    this.margin = const EdgeInsets.only(right: AppTheme.spacing24),
    this.onResumeTap,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _isHovered = false;
  String? _tmdbBackdropUrl;
  String? _tmdbTitle;
  Timer? _hoverTimer;
  final PreviewPlayer _preview = PreviewPlayer();
  bool _showPreview = false;
  TmdbResult? _tmdbResult;

  @override
  void initState() {
    super.initState();
    _loadTmdb();
  }

  Future<void> _loadTmdb() async {
    final r = await TmdbService.search(
      widget.content.title,
      year: widget.content.year,
    );
    if (r != null && mounted) {
      setState(() {
        _tmdbResult = r;
        if (r.backdropUrl.isNotEmpty) _tmdbBackdropUrl = r.backdropUrl;
        if (r.englishTitle.isNotEmpty) _tmdbTitle = r.englishTitle;
      });
    }
  }

  void _onEnter() {
    setState(() => _isHovered = true);
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 1200), _startPreview);
  }

  void _onExit() {
    setState(() => _isHovered = false);
    _hoverTimer?.cancel();
    _stopPreview();
  }

  Future<void> _startPreview() async {
    if (kIsWeb || !_isHovered || widget.content.m3u8Url.isEmpty) return;
    await _preview.init(widget.content.m3u8Url);
    if (mounted && _isHovered && _preview.controller != null) {
      setState(() => _showPreview = true);
    } else {
      _preview.dispose();
    }
  }

  void _stopPreview() {
    _preview.dispose();
    if (mounted) setState(() => _showPreview = false);
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = _tmdbTitle ?? widget.content.title;
    // Use landscape image: TMDB backdrop > bannerUrl (already landscape)
    final displayBanner = _tmdbBackdropUrl ?? widget.content.bannerUrl;
    final displaySubtitle = widget.content.subtitle.isNotEmpty
        ? widget.content.subtitle
        : widget.content.description;

    return FocusableActionDetector(
      onShowFocusHighlight: (hasFocus) {
        if (hasFocus) {
          _onEnter();
        } else {
          _onExit();
        }
      },
      onShowHoverHighlight: (hasHover) {
        if (hasHover) {
          _onEnter();
        } else {
          _onExit();
        }
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            // Handle DPAD selection similar to tap
            _handleTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_isHovered ? 1.04 : 1.0),
          transformAlignment: Alignment.center,
          margin: widget.margin,
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: widget.width * 0.565,
                decoration: BoxDecoration(
                  borderRadius: AppTheme.radius16,
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                          ...AppTheme.softShadow
                        ]
                      : [],
                  border: _isHovered
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: AppTheme.radius16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail (landscape)
                      Image.network(
                        proxyImageUrl(displayBanner),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppTheme.cardLight,
                          child: const Center(
                            child: Icon(
                              LucideIcons.image,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      // Hover video preview
                      if (_showPreview && _preview.controller != null)
                        AnimatedOpacity(
                          opacity: _showPreview ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: buildPreviewWidget(_preview.controller!),
                        ),
                      // Play icon
                      if (!_showPreview)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(
                              LucideIcons.play,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      // Progress bar
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          color: Colors.white24,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: widget.content.progress.clamp(
                              0.0,
                              1.0,
                            ),
                            child: Container(color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                displayTitle,
                style: TextStyle(
                  color: _isHovered ? Colors.white : AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                displaySubtitle,
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
      ),
    );
  }

  static int? _extractSeasonFromEpisodeName(String name) {
    final cnMatch = RegExp(r'第(\d+)季').firstMatch(name);
    if (cnMatch != null) return int.tryParse(cnMatch.group(1)!);
    final sMatch = RegExp(r'[Ss](\d{1,2})').firstMatch(name);
    if (sMatch != null) return int.tryParse(sMatch.group(1)!);
    return null;
  }

  /// Whether the saved URL is a valid persistent VOD stream (not a dead torrent proxy URL).
  static bool _isPlayableUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.contains('localhost') || lower.contains('127.0.0.1')) return false;
    return lower.contains('.m3u8') || lower.contains('.mp4') || lower.contains('http');
  }

  void _handleTap() {
    final hasResume = widget.content.resumeEpisodeIndex != null;
    final playableUrl = _isPlayableUrl(widget.content.m3u8Url);

    if (hasResume && widget.onResumeTap != null) {
      widget.onResumeTap!(
        widget.content.resumeEpisodeIndex!,
        widget.content.resumePositionSeconds ?? 0,
      ).then((_) => widget.onWatchHistoryChanged?.call());
    } else if (hasResume && playableUrl) {
      // VOD content with valid URL — resume directly in player
      final epIndex = widget.content.resumeEpisodeIndex!;
      final videoUrl =
          widget.content.episodes.isNotEmpty &&
              epIndex < widget.content.episodes.length
          ? widget.content.episodes[epIndex].url
          : widget.content.m3u8Url;
      final epName = widget.content.episodes.isNotEmpty &&
              epIndex < widget.content.episodes.length
          ? widget.content.episodes[epIndex].name
          : '';
      final seasonNum = _extractSeasonFromEpisodeName(epName);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: videoUrl,
            title: _tmdbTitle ?? widget.content.title,
            originalTitle: widget.content.title,
            episodes: widget.content.episodes,
            initialEpisodeIndex: epIndex,
            tmdbId: _tmdbResult?.id?.toString(),
            isTvShow: widget.content.episodes.length > 1,
            seasonNumber: seasonNum,
            posterUrl: widget.content.thumbnailUrl,
            seekToSeconds: widget.content.resumePositionSeconds ?? 0,
          ),
        ),
      ).then((_) => widget.onWatchHistoryChanged?.call());
    } else if (hasResume && !playableUrl) {
      if (kIsWeb) {
        // Web: can't resume torrents, open detail page instead
        DetailPage.show(
          context,
          widget.content,
          initialTmdb: _tmdbResult,
        ).then((_) => widget.onWatchHistoryChanged?.call());
      } else {
        // Torrent content with dead URL — fetch stream and go directly to player
        _resumeTorrentPlayback();
      }
    } else {
      // No resume — open detail page
      DetailPage.show(
        context,
        widget.content,
        initialTmdb: _tmdbResult,
      ).then((_) => widget.onWatchHistoryChanged?.call());
    }
  }

  Future<void> _resumeTorrentPlayback() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF1A1F2E),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFFFF3B40)),
                SizedBox(height: 16),
                Text(
                  'Finding stream...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Get TMDB info
      final tmdb = _tmdbResult ?? await TmdbService.search(
        widget.content.title,
        year: widget.content.year,
      );
      if (tmdb == null || tmdb.id == null) {
        if (mounted) Navigator.pop(context); // dismiss loading
        _openDetailPage();
        return;
      }

      final imdbId = await TmdbService.fetchImdbId(tmdb.id!, tmdb.mediaType);
      if (imdbId == null) {
        if (mounted) Navigator.pop(context);
        _openDetailPage();
        return;
      }

      final epIndex = widget.content.resumeEpisodeIndex!;
      final epName = widget.content.episodes.isNotEmpty &&
              epIndex < widget.content.episodes.length
          ? widget.content.episodes[epIndex].name
          : '';
      final seasonNum = _extractSeasonFromEpisodeName(epName) ?? 1;

      final stream = await TorrentService().fetchBestStream(
        imdbId,
        tmdb.mediaType,
        season: tmdb.mediaType == 'tv' ? seasonNum : null,
        episode: tmdb.mediaType == 'tv' ? epIndex + 1 : null,
      );

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      if (stream == null) {
        _openDetailPage();
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: '',
            title: _tmdbTitle ?? widget.content.title,
            originalTitle: widget.content.title,
            episodes: widget.content.episodes,
            initialEpisodeIndex: epIndex,
            tmdbId: tmdb.id?.toString(),
            isTvShow: widget.content.episodes.length > 1,
            seasonNumber: seasonNum,
            posterUrl: widget.content.thumbnailUrl,
            seekToSeconds: widget.content.resumePositionSeconds ?? 0,
            torrentStream: stream,
          ),
        ),
      ).then((_) => widget.onWatchHistoryChanged?.call());
    } catch (e) {
      debugPrint('[VideoCard] resumeTorrentPlayback error: $e');
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        _openDetailPage();
      }
    }
  }

  void _openDetailPage() {
    DetailPage.show(
      context,
      widget.content,
      initialTmdb: _tmdbResult,
    ).then((_) => widget.onWatchHistoryChanged?.call());
  }
}
