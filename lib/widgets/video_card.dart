import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../services/tmdb_service.dart';

class VideoCard extends StatefulWidget {
  final ContentModel content;
  const VideoCard({super.key, required this.content});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _isHovered = false;
  String? _tmdbBackdropUrl;
  String? _tmdbTitle;
  Timer? _hoverTimer;
  Player? _previewPlayer;
  VideoController? _previewController;
  bool _showPreview = false;
  TmdbResult? _tmdbResult;

  @override
  void initState() {
    super.initState();
    _loadTmdb();
  }

  Future<void> _loadTmdb() async {
    final r = await TmdbService.search(widget.content.title, year: widget.content.year);
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
    if (!_isHovered || widget.content.m3u8Url.isEmpty) return;
    final player = Player();
    final controller = VideoController(player);
    await player.setVolume(0);
    await player.open(Media(widget.content.m3u8Url));
    await player.seek(const Duration(minutes: 5));
    if (mounted && _isHovered) {
      setState(() {
        _previewPlayer = player;
        _previewController = controller;
        _showPreview = true;
      });
    } else {
      player.dispose();
    }
  }

  void _stopPreview() {
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewController = null;
    if (mounted) setState(() => _showPreview = false);
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _previewPlayer?.dispose();
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

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DetailPage(
            content: widget.content,
            initialTmdb: _tmdbResult,
          ))),
      child: MouseRegion(
        onEnter: (_) => _onEnter(),
        onExit: (_) => _onExit(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_isHovered ? 1.04 : 1.0),
          transformAlignment: Alignment.center,
          margin: const EdgeInsets.only(right: AppTheme.spacing24),
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 158,
                decoration: BoxDecoration(
                  borderRadius: AppTheme.radius16,
                  boxShadow: _isHovered ? AppTheme.softShadow : [],
                ),
                child: ClipRRect(
                  borderRadius: AppTheme.radius16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail (landscape)
                      Image.network(displayBanner, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.cardLight,
                              child: const Center(child: Icon(LucideIcons.image, color: AppTheme.textSecondary)))),
                      // Hover video preview
                      if (_showPreview && _previewController != null)
                        AnimatedOpacity(
                          opacity: _showPreview ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 400),
                          child: Video(
                            controller: _previewController!,
                            controls: NoVideoControls,
                          ),
                        ),
                      // Play icon
                      if (!_showPreview)
                        Positioned(
                          bottom: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(LucideIcons.play, color: Colors.white, size: 14),
                          ),
                        ),
                      // Progress bar
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 3,
                          color: Colors.white24,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: widget.content.progress.clamp(0.0, 1.0),
                            child: Container(color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(displayTitle,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(displaySubtitle,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
