import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/proxy_url.dart';
import '../core/responsive.dart';
import '../main.dart' show routeObserver;
import '../core/theme.dart';
import '../models/content_model.dart';
import '../models/episode.dart';
import '../pages/browse_page.dart';
import '../pages/category_page.dart';
import '../pages/my_list_page.dart';
import '../pages/profile_page.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/tmdb_service.dart';
import '../services/user_service.dart';
import '../widgets/hero_card.dart';
import '../widgets/movie_card.dart';
import '../widgets/navbar.dart';
import 'video_player_screen.dart';
import 'detail_page.dart';
import '../services/torrent_service.dart';
import '../widgets/horizontal_scroll_wrapper.dart';
import '../widgets/buttons.dart';

class HomePage extends StatefulWidget {
  final List<ContentModel> trendingMovies;
  final List<ContentModel> trendingSeries;
  final List<ContentModel> chineseAnim;
  final List<ContentModel> chineseDramas;
  final List<ContentModel> koreanDramas;
  final List<ContentModel> westernSeries;
  final List<ContentModel> hkSeries;

  const HomePage({
    super.key,
    this.trendingMovies = const [],
    this.trendingSeries = const [],
    this.chineseAnim = const [],
    this.chineseDramas = const [],
    this.koreanDramas = const [],
    this.westernSeries = const [],
    this.hkSeries = const [],
  });

  static void refreshFromLanguageChange() {
    _HomePageState._instance?._refreshContent();
  }

  static void refreshFromSourceChange() {
    _HomePageState._instance?._refreshContent();
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  static _HomePageState? _instance;
  final ApiService _api = ApiService();
  List<ContentModel> _trendingMovies = [];
  List<ContentModel> _trendingSeries = [];
  List<ContentModel> _chineseDramas = [];
  List<ContentModel> _chineseAnimation = [];
  List<ContentModel> _koreanDramas = [];
  List<ContentModel> _westernSeries = [];
  List<ContentModel> _hongKongSeries = [];
  List<Map<String, dynamic>> _watchHistory = [];
  List<ContentModel> _trendingItems = [];
  Map<int, TmdbResult> _trendingTmdb = {};
  bool _isLoading = false;
  List<ContentModel> _providerContent = [];

  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  void _refreshContent() {
    setState(() => _isLoading = true);
    _loadContent();
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    _trendingMovies = widget.trendingMovies;
    _trendingSeries = widget.trendingSeries;
    _chineseAnimation = widget.chineseAnim;
    _chineseDramas = widget.chineseDramas;
    _koreanDramas = widget.koreanDramas;
    _westernSeries = widget.westernSeries;
    _hongKongSeries = widget.hkSeries;

    _loadContent();
    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 50;
      if (isScrolled != _isScrolled) {
        setState(() => _isScrolled = isScrolled);
      }
    });

    // Subscribe to route observer to refresh watch history when returning
    WidgetsBinding.instance.addPostFrameCallback((_) {
      routeObserver.subscribe(this, ModalRoute.of(context)!);
    });
  }

  @override
  void didPopNext() {
    // Refresh watch history when returning to this page
    _refreshWatchHistory();
  }

  Future<void> _loadContent() async {
    // Load default source preference
    if (AuthService.isLoggedIn) {
      try {
        final sourceName = await UserService.getDefaultSource();
        ApiService.setDefaultSourceByName(sourceName);
      } catch (_) {}
    }

    final trendingTmdbResults = await TmdbService.fetchRecentPopularMovies(
      count: 8,
    );

    List<Map<String, dynamic>> history = [];
    if (AuthService.isLoggedIn) {
      history = await UserService.getWatchHistory();
    }

    // Fetch provider content for continue watching fallback
    final providerContent = await _api.fetchLatest();

    final trendingItems = <ContentModel>[];
    final trendingTmdbMap = <int, TmdbResult>{};
    for (int i = 0; i < trendingTmdbResults.length; i++) {
      final tmdb = trendingTmdbResults[i];
      trendingTmdbMap[i] = tmdb;
      trendingItems.add(
        ContentModel(
          title: tmdb.englishTitle,
          description: tmdb.overview,
          thumbnailUrl: tmdb.posterUrl,
          bannerUrl: tmdb.backdropUrl.isNotEmpty
              ? tmdb.backdropUrl
              : tmdb.posterUrl,
          m3u8Url: '',
          year: tmdb.year,
          rating: tmdb.voteAverage,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _watchHistory = history;
      _providerContent = providerContent;
      _trendingItems = trendingItems;
      _trendingTmdb = trendingTmdbMap;
      _isLoading = false;
    });
  }

  Future<void> _refreshWatchHistory() async {
    if (!AuthService.isLoggedIn) return;
    final history = await UserService.getWatchHistory();
    if (!mounted) return;
    setState(() {
      _watchHistory = history;
    });
  }

  /// Pull-to-refresh: reload all content and watch history.
  Future<void> _refreshAll() async {
    await _loadContent();
  }

  /// Resume a Continue Watching item with a fresh TMDB + provider match.
  /// Mirrors the profile page's _resumeWatching logic.
  static bool _isPlayableUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.contains('localhost') || lower.contains('127.0.0.1')) return false;
    return lower.contains('.m3u8') || lower.contains('.mp4') || lower.contains('http');
  }

  /// Resume a Continue Watching item with a fresh TMDB + provider match.
  /// Mirrors the profile page's _resumeWatching logic.
  Future<void> _resumeFromHistory(ContentModel item, int epIdx, int posSec) async {
    if (!mounted) return;
    final title = item.title;
    final savedSource = item.videoSourceName;

    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)));

    try {
      final tmdb = await TmdbService.search(title, year: item.year);

      // If saved source is Torrent, go straight to torrent resolution
      if (savedSource == 'Torrent') {
        if (tmdb != null && tmdb.id != null) {
          final imdbId = await TmdbService.fetchImdbId(tmdb.id!, tmdb.mediaType);
          if (imdbId != null) {
            final epName = item.episodes.isNotEmpty && epIdx < item.episodes.length
                ? item.episodes[epIdx].name
                : '';
            final seasonNum = RegExp(r'第(\d+)季').firstMatch(epName)?.group(1)
                ?? RegExp(r'[Ss](\d{1,2})').firstMatch(epName)?.group(1)
                ?? '1';

            final stream = await TorrentService().fetchBestStream(
              imdbId,
              tmdb.mediaType,
              season: tmdb.mediaType == 'tv' ? int.tryParse(seasonNum) : null,
              episode: tmdb.mediaType == 'tv' ? epIdx + 1 : null,
            );

            if (!mounted) return;
            Navigator.pop(context);

            if (stream != null) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
                videoUrl: '',
                title: item.title,
                originalTitle: title,
                episodes: item.episodes,
                initialEpisodeIndex: epIdx,
                tmdbId: tmdb.id?.toString(),
                isTvShow: item.episodes.length > 1,
                seasonNumber: int.tryParse(seasonNum),
                posterUrl: item.thumbnailUrl,
                seekToSeconds: posSec,
                torrentStream: stream,
                videoSourceName: 'Torrent',
              )));
              _refreshWatchHistory();
              return;
            }
          }
        }
        // Torrent failed — fall through to default VOD matching below
        if (mounted) Navigator.pop(context);
        showDialog(context: context, barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)));
      }

      // Try matching on the specific saved VOD source first
      ContentModel? content;
      if (savedSource != null && savedSource.isNotEmpty && savedSource != 'Torrent') {
        final savedSrc = ApiService.sources.where((s) => s.name == savedSource).firstOrNull;
        if (savedSrc != null && tmdb != null) {
          content = await ApiService().matchTmdbToProviderFromSource(tmdb, savedSrc);
        }
      }
      // Fallback to default source matching
      content ??= await ApiService().matchTmdbToProvider(
        tmdb ?? TmdbResult(englishTitle: title, overview: '', posterUrl: '', backdropUrl: ''),
      );

      if (content != null) {
        if (!mounted) return;
        Navigator.pop(context); // dismiss loading

        final videoUrl = content.episodes.isNotEmpty && epIdx < content.episodes.length
            ? content.episodes[epIdx].url
            : content.m3u8Url;
        final epName = content.episodes.isNotEmpty && epIdx < content.episodes.length
            ? content.episodes[epIdx].name
            : '';
        final seasonNum = RegExp(r'第(\d+)季').firstMatch(epName)?.group(1)
            ?? RegExp(r'[Ss](\d{1,2})').firstMatch(epName)?.group(1);

        await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
          videoUrl: videoUrl,
          title: content!.title,
          originalTitle: title,
          episodes: content.episodes,
          initialEpisodeIndex: epIdx,
          tmdbId: tmdb?.id?.toString(),
          isTvShow: content.episodes.length > 1,
          seasonNumber: seasonNum != null ? int.tryParse(seasonNum) : null,
          posterUrl: content.thumbnailUrl,
          seekToSeconds: posSec,
          videoSourceName: savedSource,
        )));
        _refreshWatchHistory();
        return;
      }

      // If content is null, check fallbacks
      final videoUrl = item.episodes.isNotEmpty && epIdx < item.episodes.length
          ? item.episodes[epIdx].url
          : item.m3u8Url;

      if (_isPlayableUrl(videoUrl)) {
        if (!mounted) return;
        Navigator.pop(context); // dismiss loading

        final epName = item.episodes.isNotEmpty && epIdx < item.episodes.length
            ? item.episodes[epIdx].name
            : '';
        final seasonNum = RegExp(r'第(\d+)季').firstMatch(epName)?.group(1)
            ?? RegExp(r'[Ss](\d{1,2})').firstMatch(epName)?.group(1);

        await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
          videoUrl: videoUrl,
          title: item.title,
          originalTitle: title,
          episodes: item.episodes,
          initialEpisodeIndex: epIdx,
          tmdbId: tmdb?.id?.toString(),
          isTvShow: item.episodes.length > 1,
          seasonNumber: seasonNum != null ? int.tryParse(seasonNum) : null,
          posterUrl: item.thumbnailUrl,
          seekToSeconds: posSec,
          videoSourceName: savedSource,
        )));
        _refreshWatchHistory();
        return;
      }

      // Torrent fallback (for items without a saved source)
      if (savedSource != 'Torrent' && tmdb != null && tmdb.id != null) {
        final imdbId = await TmdbService.fetchImdbId(tmdb.id!, tmdb.mediaType);
        if (imdbId != null) {
          final epName = item.episodes.isNotEmpty && epIdx < item.episodes.length
              ? item.episodes[epIdx].name
              : '';
          final seasonNum = RegExp(r'第(\d+)季').firstMatch(epName)?.group(1)
              ?? RegExp(r'[Ss](\d{1,2})').firstMatch(epName)?.group(1)
              ?? '1';

          final stream = await TorrentService().fetchBestStream(
            imdbId,
            tmdb.mediaType,
            season: tmdb.mediaType == 'tv' ? int.tryParse(seasonNum) : null,
            episode: tmdb.mediaType == 'tv' ? epIdx + 1 : null,
          );

          if (!mounted) return;
          Navigator.pop(context); // dismiss loading

          if (stream != null) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
              videoUrl: '',
              title: item.title,
              originalTitle: title,
              episodes: item.episodes,
              initialEpisodeIndex: epIdx,
              tmdbId: tmdb.id?.toString(),
              isTvShow: item.episodes.length > 1,
              seasonNumber: int.tryParse(seasonNum),
              posterUrl: item.thumbnailUrl,
              seekToSeconds: posSec,
              torrentStream: stream,
              videoSourceName: 'Torrent',
            )));
            _refreshWatchHistory();
            return;
          }
        } else {
          if (mounted) Navigator.pop(context);
        }
      } else {
        if (mounted) Navigator.pop(context);
      }

      // If all fails, open detail page using fallback item
      if (mounted) {
        await DetailPage.show(context, item, initialTmdb: tmdb);
        _refreshWatchHistory();
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load')));
      }
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _instance = null;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: AppTheme.accent,
                strokeWidth: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'Loading HYFLIX...',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final heroItems = _trendingItems;
    final allContent = [
      ..._trendingMovies,
      ..._trendingSeries,
      ..._chineseDramas,
      ..._chineseAnimation,
      ..._koreanDramas,
      ..._westernSeries,
      ..._hongKongSeries,
      ..._providerContent,
    ];
    final watchingItems = <ContentModel>[];
    final seenIds = <String>{};
    for (final history in _watchHistory) {
      if (watchingItems.length >= 8) break;

      final title = history['title'] as String? ?? '';
      final originalTitle = history['originalTitle'] as String? ?? '';
      final tmdbId = history['tmdbId'] as String? ?? '';
      final posterUrl = history['posterUrl'] as String? ?? '';
      final progress = (history['progress'] as num?)?.toDouble() ?? 0.0;
      final savedM3u8Url = history['m3u8Url'] as String? ?? '';
      final savedEpisodesRaw = history['episodes'] as List<dynamic>?;
      final savedVideoSourceName = history['videoSourceName'] as String? ?? '';
      final isTorrentContent = savedVideoSourceName == 'Torrent' ||
          (savedM3u8Url.isEmpty && (savedEpisodesRaw == null || savedEpisodesRaw.isEmpty));

      // Match by tmdbId first (most reliable), then by title
      // Skip matching for torrent content — use fallback path for _resumeTorrentPlayback
      ContentModel? match;
      if (!isTorrentContent && tmdbId.isNotEmpty) {
        final tmdbResult = _trendingTmdb.values
            .where((t) => t.id?.toString() == tmdbId)
            .firstOrNull;
        if (tmdbResult != null) {
          match = allContent
              .where((c) => c.title == tmdbResult.englishTitle)
              .firstOrNull;
        }
      }
      if (!isTorrentContent && match == null && originalTitle.isNotEmpty) {
        match = allContent.where((c) => c.title == originalTitle).firstOrNull;
      }
      if (!isTorrentContent) {
        match ??= allContent.where((c) => c.title == title).firstOrNull;
      }

      // Deduplicate using all available keys so the same show can't appear twice
      // even if different saves used different identifiers (tmdbId vs title).
      final dedupeKeys = <String>[
        if (tmdbId.isNotEmpty) tmdbId,
        if (originalTitle.isNotEmpty) originalTitle,
        if (title.isNotEmpty) title,
      ];
      if (dedupeKeys.any(seenIds.contains)) continue;
      seenIds.addAll(dedupeKeys);

      final episodeIndex = (history['episodeIndex'] as num?)?.toInt() ?? 0;
      final positionSeconds =
          (history['positionSeconds'] as num?)?.toInt() ?? 0;

      if (match != null) {
        watchingItems.add(
          match.copyWith(
            title: title.isNotEmpty ? title : match.title,
            thumbnailUrl: posterUrl.isNotEmpty ? posterUrl : match.thumbnailUrl,
            bannerUrl: posterUrl.isNotEmpty ? posterUrl : match.bannerUrl,
            progress: progress,
            resumeEpisodeIndex: episodeIndex,
            resumePositionSeconds: positionSeconds,
            videoSourceName: savedVideoSourceName.isNotEmpty ? savedVideoSourceName : null,
          ),
        );
      } else if (title.isNotEmpty || originalTitle.isNotEmpty) {
        final savedEpisodes = savedEpisodesRaw
                ?.map((e) => Episode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [];
        // For torrent content with no saved episodes, create placeholder episodes
        // so the resume flow can detect it as a multi-episode show
        final episodeCount = (history['episodeCount'] as num?)?.toInt() ?? 0;
        final effectiveEpisodes = savedEpisodes.isNotEmpty
            ? savedEpisodes
            : (episodeCount > 1
                ? List.generate(episodeCount, (i) => Episode(name: 'Episode ${i + 1}', url: ''))
                : const <Episode>[]);
        watchingItems.add(
          ContentModel(
            title: originalTitle.isNotEmpty ? originalTitle : title,
            subtitle: '',
            description: '',
            thumbnailUrl: posterUrl,
            bannerUrl: posterUrl,
            m3u8Url: savedM3u8Url,
            year: '',
            rating: 0,
            episodes: effectiveEpisodes,
            progress: progress,
            resumeEpisodeIndex: episodeIndex,
            resumePositionSeconds: positionSeconds,
            videoSourceName: savedVideoSourceName.isNotEmpty ? savedVideoSourceName : null,
          ),
        );
      }
    }

    return Scaffold(
      bottomNavigationBar: layout.usesBottomNav
          ? _buildBottomNavigation(context)
          : null,
      body: Stack(
        children: [
          Container(color: AppTheme.background),
          RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: const Color(0xFF1A1F2E),
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                if (heroItems.isNotEmpty)
                  HeroSection(
                    featuredContent: heroItems,
                    preloadedTmdb: _trendingTmdb,
                  )
                else
                  SizedBox(height: layout.topSafeSpacing),
                if (watchingItems.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Continue Watching',
                    height: layout.landscapeCardWidth * 0.565 + 84,
                    count: watchingItems.length,
                    builder: (i) => _ContinueWatchingCard(
                      content: watchingItems[i],
                      cardWidth: layout.landscapeCardWidth,
                      margin: EdgeInsets.only(
                        right: layout.isPhone ? 16 : AppTheme.spacing24,
                      ),
                      onResume: (epIdx, posSec) =>
                          _resumeFromHistory(watchingItems[i], epIdx, posSec),
                    ),
                  ),
                if (_trendingMovies.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Movies',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _trendingMovies.take(10).length,
                    builder: (i) => MovieCard(
                      content: _trendingMovies[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Movies',
                          fetchFunction: (p) => _api.fetchMovies(page: p),
                          initialItems: _trendingMovies,
                        ),
                      ),
                    ),
                  ),
                if (_trendingSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Series',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _trendingSeries.take(10).length,
                    builder: (i) => MovieCard(
                      content: _trendingSeries[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Series',
                          fetchFunction: (p) => _api.fetchTVSeries(page: p),
                          initialItems: _trendingSeries,
                        ),
                      ),
                    ),
                  ),
                if (_chineseDramas.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Chinese Series',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _chineseDramas.take(10).length,
                    builder: (i) => MovieCard(
                      content: _chineseDramas[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Chinese Series',
                          fetchFunction: (p) =>
                              _api.fetchChineseDramas(page: p),
                          initialItems: _chineseDramas,
                        ),
                      ),
                    ),
                  ),
                if (_chineseAnimation.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Chinese Animation',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _chineseAnimation.take(10).length,
                    builder: (i) => MovieCard(
                      content: _chineseAnimation[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Chinese Animation',
                          fetchFunction: (p) => _api.fetchAnimation(page: p),
                          initialItems: _chineseAnimation,
                        ),
                      ),
                    ),
                  ),
                if (_koreanDramas.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Korean Series',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _koreanDramas.take(10).length,
                    builder: (i) => MovieCard(
                      content: _koreanDramas[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Korean Series',
                          fetchFunction: (p) => _api.fetchKoreanDramas(page: p),
                          initialItems: _koreanDramas,
                        ),
                      ),
                    ),
                  ),
                if (_westernSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Western Series',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _westernSeries.take(10).length,
                    builder: (i) => MovieCard(
                      content: _westernSeries[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Western Series',
                          fetchFunction: (p) =>
                              _api.fetchWesternSeries(page: p),
                          initialItems: _westernSeries,
                        ),
                      ),
                    ),
                  ),
                if (_hongKongSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Hong Kong Series',
                    height: layout.posterCardWidth * 1.85 + 16,
                    count: _hongKongSeries.take(10).length,
                    builder: (i) => MovieCard(
                      content: _hongKongSeries[i],
                      width: layout.posterCardWidth,
                    ),
                    onViewAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryPage(
                          title: 'Hong Kong Series',
                          fetchFunction: (p) =>
                              _api.fetchHongKongSeries(page: p),
                          initialItems: _hongKongSeries,
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: layout.usesBottomNav ? 104 : AppTheme.spacing64,
                ),
              ],
            ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Navbar(isScrolled: _isScrolled),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSection({
    required BuildContext context,
    required String title,
    required double height,
    required int count,
    required Widget Function(int index) builder,
    VoidCallback? onViewAll,
  }) {
    final layout = ResponsiveLayout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: layout.pagePadding,
            right: layout.pagePadding,
            top: layout.sectionGap,
            bottom: layout.isPhone ? 16 : AppTheme.spacing24,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: layout.sectionTitleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onViewAll != null)
                HoverButton(
                  onTap: onViewAll,
                  backgroundColor: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: AppTheme.textSecondary,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: HorizontalScrollWrapper(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                horizontal: layout.pagePadding,
                vertical: 8,
              ),
              clipBehavior: Clip.none,
              itemCount: count,
              itemBuilder: (context, i) => builder(i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigation(BuildContext context) {
    return NavigationBar(
      height: 74,
      backgroundColor: AppTheme.surface,
      indicatorColor: AppTheme.accent.withOpacity(0.18),
      selectedIndex: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BrowsePage(
                  title: 'Movies',
                  mediaType: 'movie',
                  genres: [
                    FilterOption('All Genres', ''),
                    FilterOption('Action', '28'),
                    FilterOption('Comedy', '35'),
                    FilterOption('Romance', '10749'),
                    FilterOption('Sci-Fi', '878'),
                    FilterOption('Horror', '27'),
                    FilterOption('Drama', '18'),
                    FilterOption('Thriller', '53'),
                    FilterOption('Adventure', '12'),
                    FilterOption('Fantasy', '14'),
                    FilterOption('Crime', '80'),
                    FilterOption('Mystery', '9648'),
                  ],
                ),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyListPage()),
            );
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
            break;
        }
      },
      destinations: [
        NavigationDestination(icon: const Icon(LucideIcons.home), label: TmdbService.currentLanguage == 'zh-CN' ? '首页' : 'Home'),
        NavigationDestination(icon: const Icon(LucideIcons.compass), label: TmdbService.currentLanguage == 'zh-CN' ? '浏览' : 'Browse'),
        NavigationDestination(
          icon: const Icon(LucideIcons.listVideo),
          label: TmdbService.currentLanguage == 'zh-CN' ? '我的' : 'My List',
        ),
        NavigationDestination(icon: const Icon(LucideIcons.user), label: TmdbService.currentLanguage == 'zh-CN' ? '个人' : 'Profile'),
      ],
    );
  }
}

// ── Continue Watching Card (profile-page design) ──────────────────

class _ContinueWatchingCard extends StatefulWidget {
  final ContentModel content;
  final double cardWidth;
  final EdgeInsetsGeometry margin;
  final Future<void> Function(int episodeIndex, int seekToSeconds) onResume;

  const _ContinueWatchingCard({
    required this.content,
    required this.cardWidth,
    required this.onResume,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<_ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends State<_ContinueWatchingCard> {
  bool _hovered = false;
  bool _pressed = false;

  static String _fmtTime(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.content.title;
    final poster = widget.content.thumbnailUrl;
    final progress = widget.content.progress;
    final epIdx = widget.content.resumeEpisodeIndex ?? 0;
    final posSec = widget.content.resumePositionSeconds ?? 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () => widget.onResume(epIdx, posSec),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: _pressed
              ? (Matrix4.identity()..scale(0.97))
              : _hovered
                  ? (Matrix4.identity()..scale(1.02))
                  : Matrix4.identity(),
          transformAlignment: Alignment.center,
          margin: widget.margin,
          width: widget.cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _doubleBezel(
                  borderRadius: 6,
                  outerPadding: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.network(
                        proxyImageUrl(poster),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF111114),
                          child: Center(
                            child: Icon(LucideIcons.film,
                                color: Colors.white.withOpacity(0.15), size: 24),
                          ),
                        ),
                      ),
                      // Gradient scrim
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 80,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                            ),
                          ),
                        ),
                      ),
                      // Play button — glass morphed (visible on hover)
                      if (_hovered)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.15), width: 1),
                                ),
                                child: const Icon(LucideIcons.play,
                                    color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                      // Badges
                      Positioned(top: 10, left: 10, child: _glassBadge('E${epIdx + 1}')),
                      Positioned(top: 10, right: 10, child: _glassBadge(_fmtTime(posSec))),
                      // Progress bar with hover glow
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            boxShadow: _hovered
                                ? [
                                    BoxShadow(
                                      color: AppTheme.accent.withOpacity(0.6),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _hovered ? const Color(0xFFFFB4AA) : AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                widget.content.episodes.isNotEmpty
                    ? 'S1:E${epIdx + 1} • ${_fmtTime(posSec)} left'
                    : 'Movie • ${_fmtTime(posSec)} left',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _doubleBezel({
    required double borderRadius,
    required double outerPadding,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(outerPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius + outerPadding),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: const Color(0xFF0C0C0F),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _glassBadge(String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
