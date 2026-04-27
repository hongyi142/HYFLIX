import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../services/api_service.dart';
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

  List<ContentModel> _latest = [];
  List<ContentModel> _movies = [];
  List<ContentModel> _tvSeries = [];
  List<ContentModel> _animation = [];
  List<ContentModel> _koreanDramas = [];
  List<ContentModel> _westernSeries = [];
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
      _api.fetchLatest(page: 1),
      _api.fetchMovies(page: 1),
      _api.fetchTVSeries(page: 1),
      _api.fetchAnimation(page: 1),
      _api.fetchKoreanDramas(page: 1),
      _api.fetchWesternSeries(page: 1),
    ]);

    if (!mounted) return;
    setState(() {
      _latest = results[0];
      _movies = results[1];
      _tvSeries = results[2];
      _animation = results[3];
      _koreanDramas = results[4];
      _westernSeries = results[5];
      _isLoading = false;
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

    final heroItems = _latest.where((c) => c.m3u8Url.isNotEmpty).take(6).toList();

    // Continue watching — inject fake progress values for demo
    final progressValues = [0.65, 0.15, 0.85, 0.40, 0.90, 0.10, 0.55, 0.30];
    final watchingItems = _latest.skip(6).take(8).toList().asMap().entries.map((e) {
      return e.value.copyWith(progress: progressValues[e.key % progressValues.length]);
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          Container(color: AppTheme.background),

          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 90),

                // ── Hero ──────────────────────────────────────────────
                if (heroItems.isNotEmpty)
                  HeroSection(featuredContent: heroItems),

                // ── Continue Watching ─────────────────────────────────
                if (watchingItems.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Continue Watching',
                    height: 220,
                    itemWidth: 280,
                    count: watchingItems.length,
                    builder: (i) => VideoCard(content: watchingItems[i]),
                  ),

                // ── Movies ────────────────────────────────────────────
                if (_movies.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Popular Movies',
                    height: 310,
                    itemWidth: 150,
                    count: _movies.take(15).length,
                    builder: (i) => MovieCard(content: _movies[i]),
                  ),

                // ── TV Series ─────────────────────────────────────────
                if (_tvSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'TV Series',
                    height: 310,
                    itemWidth: 150,
                    count: _tvSeries.take(15).length,
                    builder: (i) => MovieCard(content: _tvSeries[i]),
                  ),

                // ── Animation ─────────────────────────────────────────
                if (_animation.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Animation',
                    height: 310,
                    itemWidth: 150,
                    count: _animation.take(15).length,
                    builder: (i) => MovieCard(content: _animation[i]),
                  ),

                // ── Korean Dramas ─────────────────────────────────────
                if (_koreanDramas.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Korean Dramas',
                    height: 310,
                    itemWidth: 150,
                    count: _koreanDramas.take(15).length,
                    builder: (i) => MovieCard(content: _koreanDramas[i]),
                  ),

                // ── Western Series ────────────────────────────────────
                if (_westernSeries.isNotEmpty)
                  _buildHorizontalSection(
                    title: 'Western & American Series',
                    height: 310,
                    itemWidth: 150,
                    count: _westernSeries.take(15).length,
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
