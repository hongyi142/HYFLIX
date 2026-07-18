import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../services/tmdb_service.dart';
import 'buttons.dart';

class HeroSection extends StatefulWidget {
  final List<ContentModel> featuredContent;
  final Map<int, TmdbResult>? preloadedTmdb;
  const HeroSection({
    super.key,
    required this.featuredContent,
    this.preloadedTmdb,
  });

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final Map<int, TmdbResult> _tmdbCache = {};
  Timer? _autoTimer;

  final FocusNode _playButtonFocusNode = FocusNode();
  final FocusNode _infoButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _playButtonFocusNode.addListener(_onFocusChange);
    _infoButtonFocusNode.addListener(_onFocusChange);
    if (widget.preloadedTmdb != null && widget.preloadedTmdb!.isNotEmpty) {
      _tmdbCache.addAll(widget.preloadedTmdb!);
    } else {
      _preloadTmdb();
    }
    _startAutoCarousel();
  }

  void _onFocusChange() {
    if (_playButtonFocusNode.hasFocus || _infoButtonFocusNode.hasFocus) {
      _autoTimer?.cancel();
      _autoTimer = null;
    } else {
      if (_autoTimer == null && mounted) {
        _startAutoCarousel();
      }
    }
  }

  void _startAutoCarousel() {
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % widget.featuredContent.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _playButtonFocusNode.removeListener(_onFocusChange);
    _infoButtonFocusNode.removeListener(_onFocusChange);
    _playButtonFocusNode.dispose();
    _infoButtonFocusNode.dispose();
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _preloadTmdb() async {
    for (int i = 0; i < widget.featuredContent.length; i++) {
      final result = await TmdbService.search(
        widget.featuredContent[i].title,
        year: widget.featuredContent[i].year,
      );
      if (result != null && mounted) {
        setState(() => _tmdbCache[i] = result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.featuredContent.isEmpty) return const SizedBox();
    final layout = ResponsiveLayout.of(context);

    return Container(
      height: layout.heroHeight,
      margin: EdgeInsets.zero,
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: widget.featuredContent.length,
            itemBuilder: (context, index) {
              final item = widget.featuredContent[index];
              final tmdb = _tmdbCache[index];
              final banner = tmdb?.backdropUrl.isNotEmpty == true
                  ? tmdb!.backdropUrl
                  : item.bannerUrl;
              final title = tmdb?.englishTitle.isNotEmpty == true
                  ? tmdb!.englishTitle
                  : item.title;
              final overview = (tmdb?.overview.isNotEmpty == true)
                  ? tmdb!.overview
                  : item.description;
              final genres = tmdb?.genres ?? [];
              final year = tmdb?.year ?? '';
              final rating = tmdb?.voteAverage ?? 0.0;
              final matchPercentage = rating > 0 ? '${(rating * 10).round()}% Match' : '98% Match';

              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    proxyImageUrl(banner),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppTheme.cardLight),
                  ),
                  // Gradient Overlay 1: Bottom-to-top black fade
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          const Color(0xFF0E0E0E),
                          const Color(0xFF0E0E0E).withOpacity(0.7),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 0.85],
                      ),
                    ),
                  ),
                  // Gradient Overlay 2: Left-to-right black fade for text readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF0E0E0E).withOpacity(0.85),
                          const Color(0xFF0E0E0E).withOpacity(0.4),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  // Gradient Overlay 3: Top-to-bottom dark fade for navbar visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0E0E0E).withOpacity(0.7),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25],
                      ),
                    ),
                  ),
                  // Content
                  Positioned(
                    left: layout.isPhone ? 20 : AppTheme.spacing64,
                    right: layout.isPhone ? 20 : null,
                    bottom: layout.isPhone ? 40 : 60,
                    width: layout.isPhone ? null : layout.heroContentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Metadata badges & text
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'TOP 10',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              matchPercentage,
                              style: const TextStyle(
                                color: Color(0xFF46D369),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              year.isNotEmpty ? year : item.year,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white54, width: 1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'HDR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: layout.heroTitleSize,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        // Genres text
                        if (genres.isNotEmpty) ...[
                          Text(
                            genres.join('  •  '),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          overview,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: layout.isPhone ? 13 : 14,
                            height: 1.5,
                          ),
                          maxLines: layout.isPhone ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            PrimaryButton(
                              focusNode: index == _currentPage ? _playButtonFocusNode : null,
                              text: 'Play Now',
                              icon: LucideIcons.play,
                              onTap: () => DetailPage.show(
                                context,
                                item,
                                initialTmdb: tmdb,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SecondaryButton(
                              focusNode: index == _currentPage ? _infoButtonFocusNode : null,
                              text: 'More Info',
                              icon: LucideIcons.info,
                              onTap: () => DetailPage.show(
                                context,
                                item,
                                initialTmdb: tmdb,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Centered Pagination pills
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.featuredContent.length, (
                        i,
                      ) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          height: 4,
                          width: _currentPage == i ? 24 : 6,
                          decoration: BoxDecoration(
                            color: _currentPage == i
                                ? AppTheme.accent
                                : Colors.white30,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
          // Right Arrow
          if (!layout.isPhone)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  ),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black38,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      LucideIcons.chevronRight,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
