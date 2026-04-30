import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import '../pages/video_player_screen.dart';
import '../services/tmdb_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/watchlist_service.dart';

class DetailPage extends StatefulWidget {
  final ContentModel content;
  final TmdbResult? initialTmdb;

  const DetailPage({super.key, required this.content, this.initialTmdb});

  static Future<void> show(
    BuildContext context,
    ContentModel content, {
    TmdbResult? initialTmdb,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Detail',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) =>
          DetailPage(content: content, initialTmdb: initialTmdb),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.95,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
  }

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  TmdbResult? _tmdb;
  int _selectedSeason = 1;
  final _watchlistService = WatchlistService();
  bool _isListed = false;

  @override
  void initState() {
    super.initState();
    _tmdb = widget.initialTmdb;
    if (_tmdb == null) {
      TmdbService.search(widget.content.title, year: widget.content.year).then((r) {
        if (mounted) setState(() => _tmdb = r);
      });
    }
    _checkListed();
    _watchlistService.addListener(_checkListed);
  }

  @override
  void dispose() {
    _watchlistService.removeListener(_checkListed);
    super.dispose();
  }

  void _checkListed() {
    if (mounted) {
      bool found = false;
      for (final listName in _watchlistService.listNames) {
        if (_watchlistService.isListed(listName, widget.content.title)) {
          found = true;
          break;
        }
      }
      setState(() => _isListed = found);
    }
  }

  void _showAddToListModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final lists = _watchlistService.listNames;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Save to...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...lists.map((listName) {
                    final isListed = _watchlistService.isListed(listName, widget.content.title);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(listName, style: const TextStyle(color: Colors.white)),
                      trailing: isListed
                          ? const Icon(LucideIcons.checkCircle2, color: AppTheme.accent)
                          : const Icon(LucideIcons.circle, color: Colors.white54),
                      onTap: () {
                        if (isListed) {
                          _watchlistService.removeFromList(listName, widget.content.title);
                        } else {
                          _watchlistService.addToList(listName, widget.content);
                        }
                        setModalState(() {});
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int? _extractSeasonNumber() {
    final subtitle = widget.content.subtitle;
    final match = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(subtitle);
    if (match != null) {
      final seasonStr = match.group(1)!;
      if (RegExp(r'^\d+$').hasMatch(seasonStr)) return int.tryParse(seasonStr);
      const cnNums = {
        '一': 1,
        '二': 2,
        '三': 3,
        '四': 4,
        '五': 5,
        '六': 6,
        '七': 7,
        '八': 8,
        '九': 9,
        '十': 10,
      };
      return cnNums[seasonStr];
    }
    return null;
  }

  void _play(int episodeIndex) {
    final isTvShow = widget.content.episodes.length > 1;
    final poster = _tmdb?.posterUrl.isNotEmpty == true
        ? _tmdb!.posterUrl
        : widget.content.thumbnailUrl;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: widget.content.episodes.isNotEmpty
              ? widget.content.episodes[episodeIndex].url
              : widget.content.m3u8Url,
          title: _tmdb?.englishTitle ?? widget.content.title,
          originalTitle: widget.content.title,
          episodes: widget.content.episodes,
          initialEpisodeIndex: episodeIndex,
          tmdbId: _tmdb?.id?.toString(),
          isTvShow: isTvShow,
          seasonNumber: _extractSeasonNumber() ?? 1,
          posterUrl: poster,
        ),
      ),
    );
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
    final year = _tmdb?.year ?? widget.content.year;
    final rating = _tmdb?.voteAverage ?? widget.content.rating;
    final episodes = widget.content.episodes;
    final isMultiEpisode = episodes.length > 1;

    final screenHeight = MediaQuery.of(context).size.height;
    final modalHeight = screenHeight * 0.85;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: modalHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(
                    backdrop,
                    title,
                    poster,
                    year,
                    rating,
                    genres,
                    isMultiEpisode,
                    episodes,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetadataRow(
                                year,
                                rating,
                                isMultiEpisode,
                                episodes,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                overview.isNotEmpty
                                    ? overview
                                    : 'No description available.',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 14,
                                  height: 1.6,
                                  fontWeight: FontWeight.normal,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 2,
                          child: _buildSidebarInfo(title, genres),
                        ),
                      ],
                    ),
                  ),
                  if (isMultiEpisode) ...[
                    const SizedBox(height: 36),
                    _buildEpisodesSection(episodes),
                  ],
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    String backdrop,
    String title,
    String poster,
    String year,
    double rating,
    List<String> genres,
    bool isMultiEpisode,
    List<Episode> episodes,
  ) {
    return Stack(
      children: [
        // Backdrop image
        SizedBox(
          height: 580,
          width: double.infinity,
          child: Image.network(
            backdrop,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppTheme.cardDark),
          ),
        ),
        // Gradient overlays
        Container(
          height: 580,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Color(0xCC0B0F14),
                AppTheme.background,
              ],
              stops: [0.0, 0.4, 0.75, 1.0],
            ),
          ),
        ),
        // Left gradient for readability
        Container(
          height: 580,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xAA0B0F14), Colors.transparent],
              stops: [0.0, 0.5],
            ),
          ),
        ),
        // Back button
        Positioned(
          top: 40,
          left: 20,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                LucideIcons.arrowLeft,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
        // Close button (X) - Netflix style
        Positioned(
          top: 40,
          right: 20,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(LucideIcons.x, color: Colors.white, size: 22),
            ),
          ),
        ),
        // Bottom content: Title + Buttons
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "N SERIES" badge + Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SERIES',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          letterSpacing: 4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Action buttons
                  Row(
                    children: [
                      // Play button
                      GestureDetector(
                        onTap: () => _play(0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.play,
                                color: Colors.black,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Play',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Add to List toggle
                      GestureDetector(
                        onTap: _showAddToListModal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _isListed
                                ? AppTheme.accent.withOpacity(0.2)
                                : const Color(0x662F3640),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isListed
                                  ? AppTheme.accent
                                  : Colors.white24,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isListed
                                    ? LucideIcons.check
                                    : LucideIcons.plus,
                                color: _isListed
                                    ? AppTheme.accent
                                    : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isListed ? 'Added' : 'My List',
                                style: TextStyle(
                                  color: _isListed
                                      ? AppTheme.accent
                                      : Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Rate button
                      _actionButton(LucideIcons.thumbsUp, ''),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(IconData icon, String label) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x662F3640),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(
    String year,
    double rating,
    bool isMultiEpisode,
    List<Episode> episodes,
  ) {
    return Row(
      children: [
        // Match percentage (simulated)
        if (rating > 0) ...[
          Text(
            '${(rating * 10).round()}% Match',
            style: const TextStyle(
              color: Color(0xFF46D369),
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 12),
        ],
        // Year
        if (year.isNotEmpty) ...[_metadataChip(year), const SizedBox(width: 8)],
        // Rating badge
        if (widget.content.subtitle.isNotEmpty) ...[
          _metadataChip('TV-MA'),
          const SizedBox(width: 8),
        ],
        // Episode count
        if (isMultiEpisode) ...[
          _metadataChip('${episodes.length} Episodes'),
          const SizedBox(width: 8),
        ],
        // HD badge
        _metadataChip('HD'),
      ],
    );
  }

  Widget _metadataChip(String text) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.cardLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarInfo(String title, List<String> genres) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Genres
        if (genres.isNotEmpty) ...[
          _sidebarRow('Genres:', genres.join(', ')),
          const SizedBox(height: 12),
        ],
        // Rating
        if (widget.content.rating > 0) ...[
          _sidebarRow('Rating:', widget.content.rating.toStringAsFixed(1)),
        ],
      ],
    );
  }

  Widget _sidebarRow(String label, String value) {
    return Material(
      type: MaterialType.transparency,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesSection(List<Episode> episodes) {
    // Extract season numbers from episode names
    final seasonMap = <int, List<Episode>>{};
    for (final ep in episodes) {
      final seasonMatch = RegExp(r'第(\d+)季').firstMatch(ep.name);
      final season = seasonMatch != null
          ? int.tryParse(seasonMatch.group(1)!) ?? 1
          : 1;
      seasonMap.putIfAbsent(season, () => []).add(ep);
    }
    final seasons = seasonMap.keys.toList()..sort();
    final hasSeasons = seasons.length > 1;
    final filteredEpisodes = hasSeasons
        ? (seasonMap[_selectedSeason] ?? [])
        : episodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with season dropdown
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
          child: Row(
            children: [
              const Text(
                'Episodes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 12),
              if (hasSeasons)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSeason,
                    dropdownColor: AppTheme.cardDark,
                    underline: const SizedBox(),
                    isDense: true,
                    items: seasons
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              'Season $s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedSeason = v ?? 1),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${episodes.length}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Episode list
        ...List.generate(filteredEpisodes.length, (i) {
          final globalIndex = episodes.indexOf(filteredEpisodes[i]);
          return _buildEpisodeTile(filteredEpisodes[i], globalIndex);
        }),
      ],
    );
  }

  Widget _buildEpisodeTile(Episode episode, int index) {
    final epName = episode.name.isNotEmpty
        ? episode.name
        : 'Episode ${index + 1}';
    return GestureDetector(
      onTap: () => _play(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            // Episode number
            SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Episode thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: episode.imageUrl.isNotEmpty
                  ? Image.network(
                      episode.imageUrl,
                      width: 120,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _episodePlaceholder(),
                    )
                  : _episodePlaceholder(),
            ),
            const SizedBox(width: 14),
            // Episode info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    epName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Episode ${index + 1}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.playCircle,
              color: AppTheme.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodePlaceholder() {
    return Container(
      width: 120,
      height: 68,
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        LucideIcons.play,
        color: AppTheme.textSecondary,
        size: 24,
      ),
    );
  }
}
