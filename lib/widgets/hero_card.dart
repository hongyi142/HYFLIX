import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/content_model.dart';
import '../pages/detail_page.dart';
import '../services/tmdb_service.dart';
import 'buttons.dart';

class HeroSection extends StatefulWidget {
  final List<ContentModel> featuredContent;
  const HeroSection({super.key, required this.featuredContent});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final Map<int, TmdbResult> _tmdbCache = {};
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _preloadTmdb();
    _startAutoCarousel();
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

    return Container(
      height: 580,
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing32, vertical: AppTheme.spacing24),
      decoration: BoxDecoration(
        borderRadius: AppTheme.radius16,
        boxShadow: AppTheme.softShadow,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: AppTheme.radius16,
            child: PageView.builder(
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
                // Use TMDB English overview; fall back to Chinese blurb
                final overview = (tmdb?.overview.isNotEmpty == true)
                    ? tmdb!.overview
                    : item.description;
                final genres = tmdb?.genres ?? [];
                final year = tmdb?.year ?? '';

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(banner, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: AppTheme.cardLight)),
                    // Gradient
                    // Main content gradient (bottom-left focus)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [
                            AppTheme.background,
                            AppTheme.background.withOpacity(0.8),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 0.85],
                        ),
                      ),
                    ),
                    // Top gradient for Navbar visibility
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.background.withOpacity(0.6),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.25],
                        ),
                      ),
                    ),
                    // Text Content
                    Positioned(
                      left: AppTheme.spacing64,
                      bottom: 80,
                      width: 540,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badge row
                          Row(
                            children: [
                              _badge('TRENDING NOW', AppTheme.accent),
                              if (year.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _badge(year, Colors.white24),
                              ],
                              ...genres.take(2).map((g) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _badge(g, Colors.white12),
                              )),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(title,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 12),
                          Text(overview,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              PrimaryButton(
                                text: 'Play Now',
                                icon: LucideIcons.play,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailPage(
                                      content: item,
                                      initialTmdb: tmdb,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              SecondaryButton(
                                text: 'More Info',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailPage(
                                      content: item,
                                      initialTmdb: tmdb,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Pagination pills
                          Row(
                            children: List.generate(widget.featuredContent.length, (i) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.only(right: 8),
                                height: 4,
                                width: _currentPage == i ? 24 : 6,
                                decoration: BoxDecoration(
                                  color: _currentPage == i ? AppTheme.accent : Colors.white30,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Right Arrow
          Positioned(
            right: 16, top: 0, bottom: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black38,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(LucideIcons.chevronRight, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  );
}
