import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import '../pages/video_player_screen.dart';
import '../services/tmdb_service.dart';

class DetailPage extends StatefulWidget {
  final ContentModel content;
  final TmdbResult? initialTmdb;

  const DetailPage({super.key, required this.content, this.initialTmdb});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  TmdbResult? _tmdb;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tmdb = widget.initialTmdb;
    if (_tmdb == null) {
      TmdbService.search(widget.content.title, year: widget.content.year).then((r) {
        if (mounted) setState(() { _tmdb = r; _loading = false; });
      });
    } else {
      _loading = false;
    }
  }

  void _play(int episodeIndex) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        videoUrl: widget.content.episodes.isNotEmpty
            ? widget.content.episodes[episodeIndex].url
            : widget.content.m3u8Url,
        title: _tmdb?.englishTitle ?? widget.content.title,
        episodes: widget.content.episodes,
        initialEpisodeIndex: episodeIndex,
        tmdbId: _tmdb?.id?.toString(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = _tmdb?.englishTitle.isNotEmpty == true
        ? _tmdb!.englishTitle
        : widget.content.title;
    final overview = _tmdb?.overview.isNotEmpty == true
        ? _tmdb!.overview
        : widget.content.description;
    final backdrop = _tmdb?.backdropUrl.isNotEmpty == true
        ? _tmdb!.backdropUrl
        : widget.content.bannerUrl;
    final poster = _tmdb?.posterUrl.isNotEmpty == true
        ? _tmdb!.posterUrl
        : widget.content.thumbnailUrl;
    final genres = _tmdb?.genres ?? [];
    final year = _tmdb?.year ?? '';
    final rating = _tmdb?.voteAverage ?? widget.content.rating;
    final episodes = widget.content.episodes;
    final isMultiEpisode = episodes.length > 1;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Backdrop ──────────────────────────────────────────
            Stack(
              children: [
                // Backdrop
                SizedBox(
                  height: 500,
                  width: double.infinity,
                  child: Image.network(backdrop, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: AppTheme.cardDark)),
                ),
                // Gradient
                Container(
                  height: 500,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppTheme.background],
                      stops: [0.4, 1.0],
                    ),
                  ),
                ),
                // Back button
                Positioned(
                  top: 40, left: 20,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
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
                ),
                // Bottom: Poster + Meta
                Positioned(
                  bottom: 0, left: 32, right: 32,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Poster
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(poster, width: 120, height: 180, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 120, height: 180, color: AppTheme.cardLight,
                              child: const Icon(LucideIcons.image, color: AppTheme.textSecondary),
                            )),
                      ),
                      const SizedBox(width: 24),
                      // Meta
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Row(children: [
                              if (year.isNotEmpty) _chip(year),
                              if (rating > 0) ...[
                                const SizedBox(width: 8),
                                Row(children: [
                                  const Icon(LucideIcons.star, color: Colors.amber, size: 14),
                                  const SizedBox(width: 4),
                                  Text(rating.toStringAsFixed(1),
                                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w600)),
                                ]),
                              ],
                              ...genres.take(3).map((g) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: _chip(g),
                              )),
                            ]),
                            const SizedBox(height: 16),
                            // Play button
                            GestureDetector(
                              onTap: () => _play(0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.play, color: Colors.black, size: 18),
                                    SizedBox(width: 8),
                                    Text('Play', style: TextStyle(
                                        color: Colors.black, fontWeight: FontWeight.w700, fontSize: 15)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Description ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Overview',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(overview.isNotEmpty ? overview : 'No description available.',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.7)),
                ],
              ),
            ),

            // ── Episodes ─────────────────────────────────────────────
            if (isMultiEpisode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                child: Row(
                  children: [
                    const Text('Episodes',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${episodes.length}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  itemCount: episodes.length,
                  itemBuilder: (context, i) => _EpisodeTile(
                    episode: episodes[i],
                    index: i,
                    onTap: () => _play(i),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.cardLight,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
  );
}

class _EpisodeTile extends StatefulWidget {
  final Episode episode;
  final int index;
  final VoidCallback onTap;
  const _EpisodeTile({required this.episode, required this.index, required this.onTap});

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.accent : AppTheme.cardLight,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _hovered ? AppTheme.accent : Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.episode.name.isNotEmpty ? widget.episode.name : 'Ep ${widget.index + 1}',
            style: TextStyle(
              color: _hovered ? Colors.white : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
