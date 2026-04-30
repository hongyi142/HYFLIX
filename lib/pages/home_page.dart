import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
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
import '../widgets/video_card.dart';

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
  }

  Future<void> _loadContent() async {
    final trendingTmdbResults = await TmdbService.fetchRecentPopularMovies(
      count: 8,
    );

    List<Map<String, dynamic>> history = [];
    if (AuthService.isLoggedIn) {
      history = await UserService.getWatchHistory();
    }

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
  void dispose() {
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
    ];
    final watchingItems = <ContentModel>[];
    final seenTitles = <String>{};
    for (final history in _watchHistory) {
      if (watchingItems.length >= 8) break;

      final title = history['title'] as String? ?? '';
      final originalTitle = history['originalTitle'] as String? ?? '';
      final posterUrl = history['posterUrl'] as String? ?? '';
      final progress = (history['progress'] as num?)?.toDouble() ?? 0.0;

      ContentModel? match;
      if (originalTitle.isNotEmpty) {
        match = allContent.where((c) => c.title == originalTitle).firstOrNull;
      }
      match ??= allContent.where((c) => c.title == title).firstOrNull;

      final finalTitle =
          match?.title ?? (originalTitle.isNotEmpty ? originalTitle : title);
      if (seenTitles.contains(finalTitle)) continue;
      seenTitles.add(finalTitle);

      if (match != null) {
        final episodeIndex = (history['episodeIndex'] as num?)?.toInt() ?? 0;
        final positionSeconds =
            (history['positionSeconds'] as num?)?.toInt() ?? 0;
        watchingItems.add(
          match.copyWith(
            progress: progress,
            resumeEpisodeIndex: episodeIndex,
            resumePositionSeconds: positionSeconds,
          ),
        );
      } else if (title.isNotEmpty) {
        watchingItems.add(
          ContentModel(
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
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: layout.topSafeSpacing),
                if (heroItems.isNotEmpty)
                  HeroSection(
                    featuredContent: heroItems,
                    preloadedTmdb: _trendingTmdb,
                  ),
                if (watchingItems.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Continue Watching',
                    height: layout.landscapeCardWidth * 0.565 + 72,
                    count: watchingItems.length,
                    builder: (i) => VideoCard(
                      content: watchingItems[i],
                      width: layout.landscapeCardWidth,
                      margin: EdgeInsets.only(
                        right: layout.isPhone ? 16 : AppTheme.spacing24,
                      ),
                      onWatchHistoryChanged: _refreshWatchHistory,
                    ),
                  ),
                if (_trendingMovies.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Movies',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_trendingSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Series',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_chineseDramas.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Chinese Series',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_chineseAnimation.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Chinese Animation',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_koreanDramas.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Korean Series',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_westernSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Western Series',
                    height: layout.posterCardWidth * 1.85,
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
                        ),
                      ),
                    ),
                  ),
                if (_hongKongSeries.isNotEmpty)
                  _buildHorizontalSection(
                    context: context,
                    title: 'Top Trending Hong Kong Series',
                    height: layout.posterCardWidth * 1.85,
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
                GestureDetector(
                  onTap: onViewAll,
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
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
            itemCount: count,
            itemBuilder: (context, i) => builder(i),
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
                  baseTypeId: 1,
                  subTypes: [
                    FilterOption('All Movies', '1'),
                    FilterOption('Action', '5'),
                    FilterOption('Comedy', '6'),
                    FilterOption('Romance', '7'),
                    FilterOption('Sci-Fi', '8'),
                    FilterOption('Horror', '9'),
                    FilterOption('Drama', '10'),
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
      destinations: const [
        NavigationDestination(icon: Icon(LucideIcons.home), label: 'Home'),
        NavigationDestination(icon: Icon(LucideIcons.compass), label: 'Browse'),
        NavigationDestination(
          icon: Icon(LucideIcons.listVideo),
          label: 'My List',
        ),
        NavigationDestination(icon: Icon(LucideIcons.user), label: 'Profile'),
      ],
    );
  }
}
