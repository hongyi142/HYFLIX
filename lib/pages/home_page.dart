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
    final results = await Future.wait([
      _api.fetchMatchedRecentPopularMovies(),
      _api.fetchMatchedRecentPopularTVSeries(),
      _api.fetchMatchedRecentPopularChineseDramas(),
      _api.fetchMatchedRecentPopularChineseAnimation(),
      _api.fetchMatchedRecentPopularKoreanDramas(),
      _api.fetchMatchedRecentPopularWesternSeries(),
    ]);

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
      _trendingMovies = results[0];
      _trendingSeries = results[1];
      _chineseDramas = results[2];
      _chineseAnimation = results[3];
      _koreanDramas = results[4];
      _westernSeries = results[5];
      _watchHistory = history;
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
    ];
    final watchingItems = <ContentModel>[];
    for (final history in _watchHistory.take(8)) {
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
          title: originalTitle.isNotEmpty ? originalTitle : title,
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
                    title: 'Top 10 Trending Movies',
                    height: 310,
                    itemWidth: 150,
                    count: _trendingMovies.take(10).length,
                    builder: (i) => MovieCard(content: _trendingMovies[i]),
                  ),

                // ── TV Series ─────────────────────────────────────────
                if (_trendingSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top 10 Trending TV Series',
                    height: 310,
                    itemWidth: 150,
                    count: _trendingSeries.take(10).length,
                    builder: (i) => MovieCard(content: _trendingSeries[i]),
                  ),

                // ── Animation ─────────────────────────────────────────
                if (_chineseDramas.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top 10 Trending Chinese Dramas',
                    height: 310,
                    itemWidth: 150,
                    count: _chineseDramas.take(10).length,
                    builder: (i) => MovieCard(content: _chineseDramas[i]),
                  ),

                if (_chineseAnimation.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top 10 Trending Chinese Animation',
                    height: 310,
                    itemWidth: 150,
                    count: _chineseAnimation.take(10).length,
                    builder: (i) => MovieCard(content: _chineseAnimation[i]),
                  ),

                // ── Korean Dramas ─────────────────────────────────────
                if (_koreanDramas.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top 10 Trending K-Dramas',
                    height: 310,
                    itemWidth: 150,
                    count: _koreanDramas.take(10).length,
                    builder: (i) => MovieCard(content: _koreanDramas[i]),
                  ),

                // ── Western Series ────────────────────────────────────
                if (_westernSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Top 10 Trending Western Series',
                    height: 310,
                    itemWidth: 150,
                    count: _westernSeries.take(10).length,
                    builder: (i) => MovieCard(content: _westernSeries[i]),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacing32,
            top: AppTheme.spacing48,
            bottom: AppTheme.spacing24,
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
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
