import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/navbar.dart';
import '../widgets/hero_card.dart';
import '../widgets/video_card.dart';
import '../widgets/movie_card.dart';
import '../pages/category_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
  bool _isLoading = true;

  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 50;
      if (isScrolled != _isScrolled) {
        setState(() => _isScrolled = isScrolled);
      }
    });
  }

  Future<void> _loadContent() async {
    // Fetch recent popular movies for hero section
    final trendingTmdbResults = await TmdbService.fetchRecentPopularMovies(count: 8);

    // Load watch history for Continue Watching section
    List<Map<String, dynamic>> history = [];
    if (AuthService.isLoggedIn) {
      history = await UserService.getWatchHistory();
    }

    // Convert trending TMDB results to ContentModel for hero section
    final trendingItems = <ContentModel>[];
    final trendingTmdbMap = <int, TmdbResult>{};
    for (int i = 0; i < trendingTmdbResults.length; i++) {
      final tmdb = trendingTmdbResults[i];
      trendingTmdbMap[i] = tmdb;
      trendingItems.add(ContentModel(
        title: tmdb.englishTitle,
        description: tmdb.overview,
        thumbnailUrl: tmdb.posterUrl,
        bannerUrl: tmdb.backdropUrl.isNotEmpty ? tmdb.backdropUrl : tmdb.posterUrl,
        m3u8Url: '',
        year: tmdb.year,
        rating: tmdb.voteAverage,
      ));
    }

    if (!mounted) return;
    setState(() {
      _watchHistory = history;
      _trendingItems = trendingItems;
      _trendingTmdb = trendingTmdbMap;
      _isLoading = false;
    });

    _loadCategoriesProgressively();
  }

  void _loadCategoriesProgressively() {
    // Kick off first two concurrently
    _api.fetchMatchedRecentPopularMovies(count: 10).then((res) {
      if (mounted) setState(() => _trendingMovies = res);
    });
    _api.fetchMatchedRecentPopularTVSeries(count: 10).then((res) {
      if (mounted) setState(() => _trendingSeries = res);
    });

    // Kick off the rest sequentially so we don't spam the network
    Future.microtask(() async {
      final chineseDramas = await _api.fetchMatchedRecentPopularChineseDramas(count: 10);
      if (mounted) setState(() => _chineseDramas = chineseDramas);
      
      final chineseAnimation = await _api.fetchMatchedRecentPopularChineseAnimation(count: 10);
      if (mounted) setState(() => _chineseAnimation = chineseAnimation);

      final koreanDramas = await _api.fetchMatchedRecentPopularKoreanDramas(count: 10);
      if (mounted) setState(() => _koreanDramas = koreanDramas);

      final westernSeries = await _api.fetchMatchedRecentPopularWesternSeries(count: 10);
      if (mounted) setState(() => _westernSeries = westernSeries);

      final hkSeries = await _api.fetchMatchedRecentPopularHongKongSeries(count: 10);
      if (mounted) setState(() => _hongKongSeries = hkSeries);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2),
              const SizedBox(height: 24),
              Text('Loading HYFLIX...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final heroItems = _trendingItems;

    // Continue watching — match watch history with loaded content
    final allContent = [
      ..._trendingMovies,
      ..._trendingSeries,
      ..._chineseDramas,
      ..._chineseAnimation,
      ..._koreanDramas,
      ..._westernSeries,
      ..._hongKongSeries,
    ];
    final watchingItems = <ContentModel>[];
    final seenTitles = <String>{};
    for (final history in _watchHistory) {
      if (watchingItems.length >= 8) break;

      final title = history['title'] as String? ?? '';
      final originalTitle = history['originalTitle'] as String? ?? '';
      final posterUrl = history['posterUrl'] as String? ?? '';
      final progress = (history['progress'] as num?)?.toDouble() ?? 0.0;
      // Try matching by original title first (Chinese), then by English title
      ContentModel? match;
      if (originalTitle.isNotEmpty) {
        match = allContent.where((c) => c.title == originalTitle).firstOrNull;
      }
      match ??= allContent.where((c) => c.title == title).firstOrNull;

      final finalTitle = match?.title ?? (originalTitle.isNotEmpty ? originalTitle : title);
      if (seenTitles.contains(finalTitle)) continue;
      seenTitles.add(finalTitle);

      if (match != null) {
        final episodeIndex = (history['episodeIndex'] as num?)?.toInt() ?? 0;
        final positionSeconds = (history['positionSeconds'] as num?)?.toInt() ?? 0;
        watchingItems.add(match.copyWith(
          progress: progress,
          resumeEpisodeIndex: episodeIndex,
          resumePositionSeconds: positionSeconds,
        ));
      } else if (title.isNotEmpty) {
        // Fallback: create a minimal ContentModel from history data
        watchingItems.add(ContentModel(
          title: finalTitle,
          subtitle: '',
          description: '',
          thumbnailUrl: posterUrl,
          bannerUrl: posterUrl,
          m3u8Url: '',
          year: '',
          rating: 0,
          episodes: const [],
          progress: progress,
        ));
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(color: AppTheme.background),

          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // ── Hero ──────────────────────────────────────────────
                if (heroItems.isNotEmpty)
                  HeroSection(featuredContent: heroItems, preloadedTmdb: _trendingTmdb),

                // ── Continue Watching ─────────────────────────────────
                if (watchingItems.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Continue Watching',
                    height: 220,
                    itemWidth: 280,
                    count: watchingItems.length,
                    builder: (i) => VideoCard(
                      content: watchingItems[i],
                      onWatchHistoryChanged: _refreshWatchHistory,
                    ),
                  ),

                // ── Movies ────────────────────────────────────────────
                if (_trendingMovies.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Movies',
                    height: 310,
                    itemWidth: 150,
                    count: _trendingMovies.take(10).length,
                    builder: (i) => MovieCard(content: _trendingMovies[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Movies', fetchFunction: (p) => _api.fetchMovies(page: p))
                    )),
                  ),

                // ── TV Series ─────────────────────────────────────────
                if (_trendingSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Series',
                    height: 310,
                    itemWidth: 150,
                    count: _trendingSeries.take(10).length,
                    builder: (i) => MovieCard(content: _trendingSeries[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Series', fetchFunction: (p) => _api.fetchTVSeries(page: p))
                    )),
                  ),

                // ── Animation ─────────────────────────────────────────
                if (_chineseDramas.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Chinese Series',
                    height: 310,
                    itemWidth: 150,
                    count: _chineseDramas.take(10).length,
                    builder: (i) => MovieCard(content: _chineseDramas[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Chinese Series', fetchFunction: (p) => _api.fetchChineseDramas(page: p))
                    )),
                  ),

                if (_chineseAnimation.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Chinese Animation',
                    height: 310,
                    itemWidth: 150,
                    count: _chineseAnimation.take(10).length,
                    builder: (i) => MovieCard(content: _chineseAnimation[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Chinese Animation', fetchFunction: (p) => _api.fetchAnimation(page: p))
                    )),
                  ),

                // ── Korean Dramas ─────────────────────────────────────
                if (_koreanDramas.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Korean Series',
                    height: 310,
                    itemWidth: 150,
                    count: _koreanDramas.take(10).length,
                    builder: (i) => MovieCard(content: _koreanDramas[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Korean Series', fetchFunction: (p) => _api.fetchKoreanDramas(page: p))
                    )),
                  ),

                // ── Western Series ────────────────────────────────────
                if (_westernSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Western Series',
                    height: 310,
                    itemWidth: 150,
                    count: _westernSeries.take(10).length,
                    builder: (i) => MovieCard(content: _westernSeries[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Western Series', fetchFunction: (p) => _api.fetchWesternSeries(page: p))
                    )),
                  ),

                // ── Hong Kong Series ──────────────────────────────────
                if (_hongKongSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top Trending Hong Kong Series',
                    height: 310,
                    itemWidth: 150,
                    count: _hongKongSeries.take(10).length,
                    builder: (i) => MovieCard(content: _hongKongSeries[i]),
                    onViewAll: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CategoryPage(title: 'Hong Kong Series', fetchFunction: (p) => _api.fetchHongKongSeries(page: p))
                    )),
                  ),

                const SizedBox(height: AppTheme.spacing64),
              ],
            ),
          ),

          // Fixed Navbar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Navbar(isScrolled: _isScrolled),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSection({
    required String title,
    required double height,
    required double itemWidth,
    required int count,
    required Widget Function(int index) builder,
    VoidCallback? onViewAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacing32,
            right: AppTheme.spacing32,
            top: AppTheme.spacing48,
            bottom: AppTheme.spacing24,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: const Row(
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
                      Icon(Icons.arrow_forward_ios, color: AppTheme.textSecondary, size: 12),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing32),
            itemCount: count,
            itemBuilder: (context, i) => builder(i),
          ),
        ),
      ],
    );
  }
}
