import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/tmdb_service.dart';
import '../services/user_service.dart';
import 'home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _loadData();
  }

  Future<void> _loadData() async {
    final api = ApiService();
    try {
      // Load language preference before fetching content
      if (AuthService.isLoggedIn) {
        final lang = await UserService.getLanguage();
        TmdbService.setLanguage(lang);
      }
      final results = await Future.wait([
        api.fetchMatchedTrendingMovies(count: 10),
        api.fetchMatchedTrendingTVSeries(count: 10),
        api.fetchMatchedRecentPopularChineseAnimation(count: 10),
        api.fetchMatchedRecentPopularChineseDramas(count: 10),
        api.fetchMatchedRecentPopularKoreanDramas(count: 10),
        api.fetchMatchedRecentPopularWesternSeries(count: 10),
        api.fetchMatchedRecentPopularHongKongSeries(count: 10, withinDays: 365),
      ]);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomePage(
              trendingMovies: results[0],
              trendingSeries: results[1],
              chineseAnim: results[2],
              chineseDramas: results[3],
              koreanDramas: results[4],
              westernSeries: results[5],
              hkSeries: results[6],
            ),
            transitionDuration: const Duration(milliseconds: 800),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } catch (e) {
      // In case of complete failure, navigate to empty HomePage and let it handle errors/retry
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: ScaleTransition(
          scale: _animation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
            ),
            child: const Text(
              'HYFLIX',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
