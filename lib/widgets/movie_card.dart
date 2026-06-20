import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lucide_icons/lucide_icons.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../services/tmdb_service.dart';
import '../services/video_preview.dart';
import 'video_preview_widget.dart';

class MovieCard extends StatefulWidget {
  final ContentModel content;
  final double? width;
  final EdgeInsetsGeometry? margin;

  const MovieCard({
    super.key,
    required this.content,
    this.width = 150,
    this.margin = const EdgeInsets.only(right: AppTheme.spacing16),
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _isHovered = false;
  String? _tmdbPosterUrl;
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
    final r = await TmdbService.search(widget.content.title, year: widget.content.year);
    if (r != null && mounted) {
      setState(() {
        _tmdbResult = r;
        if (r.posterUrl.isNotEmpty) _tmdbPosterUrl = r.posterUrl;
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
    final displayPoster = _tmdbPosterUrl ?? widget.content.thumbnailUrl;
    final displayTitle = _tmdbTitle ?? widget.content.title;

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
            DetailPage.show(context, widget.content, initialTmdb: _tmdbResult);
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: () => DetailPage.show(context, widget.content, initialTmdb: _tmdbResult),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          transformAlignment: Alignment.center,
          margin: widget.margin,
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Container(
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
                        Image.network(proxyImageUrl(displayPoster), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: AppTheme.cardLight,
                                child: const Center(child: Icon(LucideIcons.image, color: AppTheme.textSecondary)))),
                        // Video preview on hover
                        if (_showPreview && _preview.controller != null)
                          AnimatedOpacity(
                            opacity: 1.0,
                            duration: const Duration(milliseconds: 400),
                            child: buildPreviewWidget(_preview.controller!),
                          ),
                        // Hover overlay when NOT showing video
                        if (!_showPreview)
                          AnimatedOpacity(
                            opacity: _isHovered ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(LucideIcons.play, color: Colors.white, size: 36),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(displayTitle,
                  style: TextStyle(
                      color: _isHovered ? Colors.white : AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Text(widget.content.rating > 0 ? widget.content.rating.toStringAsFixed(1) : '–',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 3),
                const Icon(LucideIcons.star, color: Colors.amber, size: 11),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
