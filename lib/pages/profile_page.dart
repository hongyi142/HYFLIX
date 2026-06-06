import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/proxy_url.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../pages/detail_page.dart';
import '../pages/settings_page.dart';
import '../pages/video_player_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/horizontal_scroll_wrapper.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with TickerProviderStateMixin {
  UserProfile? _profile;
  List<Map<String, dynamic>> _history = [];
  List<String> _favouriteIds = [];
  List<TmdbResult?> _favouriteTmdb = [];
  bool _loading = true;

  int _watchStreak = 0;
  double _completionRate = 0;
  int _totalShowsWatched = 0;
  int _showsCompleted = 0;

  final ScrollController _continueScrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  // Staggered entry animations
  late final AnimationController _staggerController;
  late final List<Animation<double>> _fadeAnims;
  late final List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // 6 sections to stagger: header, stats, continue, recent, watchlist, bottom
    _fadeAnims = List.generate(6, (i) {
      final start = (i * 0.12).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: const Cubic(0.32, 0.72, 0, 1)),
      );
    });
    _slideAnims = List.generate(6, (i) {
      final start = (i * 0.12).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: const Cubic(0.32, 0.72, 0, 1)),
      ));
    });
    _loadData();
    _continueScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || !_continueScrollController.hasClients) return;
    final pos = _continueScrollController.position;
    final canLeft = pos.pixels > 20;
    final canRight = pos.pixels < pos.maxScrollExtent - 20;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollContinue(bool scrollLeft) {
    if (!_continueScrollController.hasClients || !mounted) return;
    final delta = scrollLeft ? -320.0 : 320.0;
    _continueScrollController.animateTo(
      (_continueScrollController.offset + delta).clamp(
        0,
        _continueScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 500),
      curve: const Cubic(0.32, 0.72, 0, 1),
    );
  }

  Future<void> _loadData() async {
    Map<String, dynamic>? profileData;
    List<Map<String, dynamic>> history = [];
    List<String> favs = [];

    try { profileData = await UserService.getProfile(); } catch (e) { debugPrint('[Profile] getProfile: $e'); }
    try { history = await UserService.getWatchHistory(); } catch (e) { debugPrint('[Profile] getHistory: $e'); }
    try { favs = await UserService.getFavouriteIds(); } catch (e) { debugPrint('[Profile] getFavs: $e'); }

    if (!mounted) return;
    setState(() {
      final uid = AuthService.uid;
      if (profileData != null && uid != null) {
        try { _profile = UserProfile.fromMap(uid, profileData); } catch (_) {
          _profile = UserProfile(uid: uid, email: AuthService.email ?? '', displayName: AuthService.displayName ?? '');
        }
      } else {
        _profile = UserProfile(uid: AuthService.uid ?? '', email: AuthService.email ?? '', displayName: AuthService.displayName ?? '');
      }
      _history = history;
      _favouriteIds = favs;
      _computeStats();
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onScroll();
        _staggerController.forward();
      }
    });

    if (favs.isNotEmpty) {
      final results = await Future.wait(
        favs.map((id) async { try { return await TmdbService.search(id); } catch (_) { return null; } }),
      );
      if (mounted) setState(() { _favouriteTmdb = results; });
    }
  }

  void _computeStats() {
    final now = DateTime.now();
    final dates = _history
        .map((h) => h['lastWatched']?.toString())
        .where((d) => d != null && d.isNotEmpty)
        .map((d) { try { return DateTime.parse(d!); } catch (_) { return null; } })
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    _watchStreak = 0;
    if (dates.isNotEmpty) {
      var checkDate = DateTime(now.year, now.month, now.day);
      if (dates.first != checkDate) checkDate = checkDate.subtract(const Duration(days: 1));
      for (final date in dates) {
        if (date == checkDate) { _watchStreak++; checkDate = checkDate.subtract(const Duration(days: 1)); }
        else if (date.isBefore(checkDate)) break;
      }
    }

    _totalShowsWatched = _history.length;
    _showsCompleted = _history.where((h) => ((h['progress'] as num?)?.toDouble() ?? 0) >= 0.9).length;
    _completionRate = _totalShowsWatched > 0 ? _showsCompleted / _totalShowsWatched : 0;
  }

  String _fmtTime(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String _fmtMonth(DateTime d) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month]} ${d.year}';
  }

  Future<void> _resumeWatching(Map<String, dynamic> item) async {
    final title = item['originalTitle'] as String? ?? item['title'] as String? ?? '';
    final epIdx = (item['episodeIndex'] as num?)?.toInt() ?? 0;
    final posSec = (item['positionSeconds'] as num?)?.toInt() ?? 0;
    if (!mounted) return;

    showDialog(context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2)));

    try {
      final content = await ApiService().matchTmdbToProvider(
        await TmdbService.search(title) ?? TmdbResult(englishTitle: title, overview: '', posterUrl: '', backdropUrl: ''),
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (content == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Content not found'))); return; }

      final videoUrl = content.episodes.isNotEmpty && epIdx < content.episodes.length ? content.episodes[epIdx].url : content.m3u8Url;
      final epName = content.episodes.isNotEmpty && epIdx < content.episodes.length ? content.episodes[epIdx].name : '';
      final seasonNum = RegExp(r'第(\d+)季').firstMatch(epName)?.group(1) ?? RegExp(r'[Ss](\d{1,2})').firstMatch(epName)?.group(1);

      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
        videoUrl: videoUrl, title: content.title, originalTitle: title, episodes: content.episodes,
        initialEpisodeIndex: epIdx, tmdbId: null, isTvShow: content.episodes.length > 1,
        seasonNumber: seasonNum != null ? int.tryParse(seasonNum) : null,
        posterUrl: content.thumbnailUrl, seekToSeconds: posSec,
      )));
    } catch (_) {
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load'))); }
    }
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _continueScrollController.dispose();
    super.dispose();
  }

  // ── Stagger wrapper ──────────────────────────────────────────────

  Widget _stagger(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnims[index].value,
          child: Transform.translate(
            offset: Offset(0, _slideAnims[index].value.dy * 60),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF050507),
      body: _loading
          ? _buildSkeleton(layout)
          : Stack(
              children: [
                // Ambient radial glow background
                Positioned.fill(child: _buildAmbientBackground()),
                // Content
                ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _stagger(0, _buildHero(layout)),
                    _stagger(1, _buildStats(layout)),
                    if (_history.isNotEmpty) _stagger(2, _buildContinueWatching(layout)),
                    _stagger(3, _buildRecentlyWatched(layout)),
                    _stagger(4, _buildWatchlist(layout)),
                    _stagger(5, const SizedBox(height: 80)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildAmbientBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.5, -0.8),
          radius: 1.5,
          colors: [
            AppTheme.accent.withOpacity(0.035),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  // ── Skeleton ─────────────────────────────────────────────────────

  Widget _buildSkeleton(ResponsiveLayout layout) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(layout.pagePadding, 80, layout.pagePadding, 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _skelBox(56, 56, round: true),
              const SizedBox(height: 32),
              _skelBox(260, 36),
              const SizedBox(height: 12),
              _skelBox(160, 16),
              const SizedBox(height: 28),
              _skelBox(130, 28),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: Row(
            children: List.generate(4, (_) => Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                height: 130,
                decoration: BoxDecoration(
                  color: const Color(0xFF111114),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            )),
          ),
        ),
      ],
    );
  }

  Widget _skelBox(double w, double h, {bool round = false}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        borderRadius: round ? BorderRadius.circular(28) : BorderRadius.circular(12),
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────

  Widget _buildHero(ResponsiveLayout layout) {
    final name = _profile?.displayName ?? 'User';
    final email = _profile?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final memberSince = _profile?.createdAt != null
        ? 'Member since ${_fmtMonth(_profile!.createdAt!)}'
        : '';

    return Container(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 72, layout.pagePadding, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nav row
          Row(
            children: [
              _glassNavBtn(LucideIcons.arrowLeft, () => Navigator.pop(context)),
              const Spacer(),
              _glassNavBtn(LucideIcons.settings, () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
            ],
          ),
          const SizedBox(height: 56),
          // Avatar — Double-Bezel
          _doubleBezel(
            borderRadius: 28,
            outerPadding: 4,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accent.withOpacity(0.15),
                    AppTheme.accent.withOpacity(0.05),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Eyebrow tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'PROFILE',
              style: TextStyle(
                color: AppTheme.accent.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.0,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          // Handle
          Text(
            '@${email.contains('@') ? email.split('@').first : name.toLowerCase().replaceAll(' ', '')}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
          if (memberSince.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(LucideIcons.calendar, color: Colors.white.withOpacity(0.2), size: 13),
                const SizedBox(width: 8),
                Text(
                  memberSince,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _glassNavBtn(IconData icon, VoidCallback onTap) {
    return _MagneticBtn(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.6), size: 17),
          ),
        ),
      ),
    );
  }

  // ── Stats — Asymmetric Bento ─────────────────────────────────────

  Widget _buildStats(ResponsiveLayout layout) {
    final rate = (_completionRate * 100).round();
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final todayWd = now.weekday - 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 16, layout.pagePadding, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = 14.0;
          if (layout.isPhone) {
            // Phone: 2x2 grid
            final tileW = (constraints.maxWidth - gap) / 2;
            return Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statCard(tileW, 'WATCH TIME', _fmtTime(_profile?.watchTimeSeconds ?? 0), LucideIcons.clock),
                      SizedBox(width: gap),
                      _statCard(tileW, 'COMPLETION', '$rate%', LucideIcons.pieChart),
                    ],
                  ),
                ),
                SizedBox(height: gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statCard(tileW, 'SHOWS', '$_totalShowsWatched', LucideIcons.clapperboard),
                      SizedBox(width: gap),
                      _streakCard(tileW, days, todayWd),
                    ],
                  ),
                ),
              ],
            );
          }
          // Desktop: 4-col asymmetric bento
          final col1 = (constraints.maxWidth - gap * 3) * 0.3;
          final col2 = (constraints.maxWidth - gap * 3) * 0.2;
          final col3 = (constraints.maxWidth - gap * 3) * 0.2;
          final col4 = (constraints.maxWidth - gap * 3) * 0.3;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statCard(col1, 'WATCH TIME', _fmtTime(_profile?.watchTimeSeconds ?? 0), LucideIcons.clock),
                SizedBox(width: gap),
                _statCard(col2, 'COMPLETION', '$rate%', LucideIcons.pieChart),
                SizedBox(width: gap),
                _statCard(col3, 'SHOWS', '$_totalShowsWatched', LucideIcons.clapperboard),
                SizedBox(width: gap),
                _streakCard(col4, days, todayWd),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(double width, String label, String value, IconData icon) {
    return _MagneticBtn(
      child: SizedBox(
        width: width,
        child: _doubleBezel(
          borderRadius: 22,
          outerPadding: 3,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              color: const Color(0xFF0C0C0F),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, color: AppTheme.accent.withOpacity(0.5), size: 14),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _streakCard(double width, List<String> days, int todayWd) {
    return _MagneticBtn(
      child: SizedBox(
        width: width,
        child: _doubleBezel(
          borderRadius: 22,
          outerPadding: 3,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              color: const Color(0xFF0C0C0F),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(LucideIcons.flame, color: AppTheme.accent.withOpacity(0.5), size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'STREAK',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Text(
                  '$_watchStreak day${_watchStreak == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final active = i <= todayWd && i >= todayWd - _watchStreak + 1 && _watchStreak > 0;
                    return Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active
                            ? AppTheme.accent.withOpacity(0.15)
                            : Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active
                              ? AppTheme.accent.withOpacity(0.35)
                              : Colors.white.withOpacity(0.06),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: active
                            ? Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent,
                                  borderRadius: BorderRadius.circular(3.5),
                                ),
                              )
                            : Text(
                                days[i],
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.2),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Double-Bezel Architecture ────────────────────────────────────

  Widget _doubleBezel({
    required double borderRadius,
    required double outerPadding,
    required Widget child,
  }) {
    final innerRadius = borderRadius - outerPadding;
    return Container(
      padding: EdgeInsets.all(outerPadding),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(innerRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.02),
              blurRadius: 0,
              spreadRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(innerRadius),
          child: child,
        ),
      ),
    );
  }

  // ── Continue Watching ──────────────────────────────────────────────

  Widget _buildContinueWatching(ResponsiveLayout layout) {
    final items = _history.take(8).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final cardW = layout.isPhone ? 260.0 : 300.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.pagePadding, 48, layout.pagePadding, 0),
          child: Row(children: [
            // Eyebrow + Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: AppTheme.accent.withOpacity(0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Continue Watching',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ),
            ),
            _pillBtn('Clear', _clearContinueWatching),
            if (_canScrollLeft) _scrollArrow(LucideIcons.chevronLeft, () => _scrollContinue(true)),
            if (_canScrollRight) _scrollArrow(LucideIcons.chevronRight, () => _scrollContinue(false)),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: layout.isPhone ? 200 : 240,
          child: HorizontalScrollWrapper(
            controller: _continueScrollController,
            child: ListView.builder(
              controller: _continueScrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
              itemCount: items.length,
              itemBuilder: (ctx, i) => _continueCard(items[i], cardW),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillBtn(String label, VoidCallback onTap) {
    return _MagneticBtn(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Future<void> _clearContinueWatching() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111114),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          'Clear Continue Watching',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5),
        ),
        content: Text(
          'This will remove all your continue watching history. This action cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.45), height: 1.7, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.accent.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('Clear', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await UserService.clearWatchHistory();
      setState(() => _history = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Continue watching cleared'),
            backgroundColor: const Color(0xFF111114),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
  }

  Widget _scrollArrow(IconData icon, VoidCallback onTap) {
    return _MagneticBtn(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.4), size: 15),
      ),
    );
  }

  Widget _continueCard(Map<String, dynamic> item, double cardW) {
    final title = item['title'] as String? ?? '';
    final poster = item['posterUrl'] as String? ?? '';
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
    final epIdx = (item['episodeIndex'] as num?)?.toInt() ?? 0;
    final posSec = (item['positionSeconds'] as num?)?.toInt() ?? 0;

    return _MagneticBtn(
      onTap: () => _resumeWatching(item),
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _doubleBezel(
                borderRadius: 20,
                outerPadding: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(
                      proxyImageUrl(poster),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF111114),
                        child: Center(child: Icon(LucideIcons.film, color: Colors.white.withOpacity(0.15), size: 24)),
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
                    // Play button — glass morphed
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
                              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                            ),
                            child: const Icon(LucideIcons.play, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ),
                    // Badges
                    Positioned(top: 10, left: 10, child: _glassBadge('E${epIdx + 1}')),
                    Positioned(top: 10, right: 10, child: _glassBadge(_fmtTime(posSec))),
                    // Progress bar
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
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
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              '${(progress * 100).round()}% watched',
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // ── Recently Watched ──────────────────────────────────────────────

  Widget _buildRecentlyWatched(ResponsiveLayout layout) {
    final items = _history.take(18).toList();
    final cols = layout.isPhone ? 3 : 6;
    final tileW = (layout.width - layout.pagePadding * 2 - 14 * (cols - 1)) / cols;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 56, layout.pagePadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow + Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'HISTORY',
              style: TextStyle(
                color: AppTheme.accent.withOpacity(0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Recently Watched',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 24),
          if (items.isEmpty)
            _emptyState(LucideIcons.clock, 'No watch history yet', 'Shows you watch will appear here')
          else
            Wrap(
              spacing: 14,
              runSpacing: 20,
              children: items.map((item) => SizedBox(width: tileW, child: _recentCard(item))).toList(),
            ),
        ],
      ),
    );
  }

  Widget _recentCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? '';
    final poster = item['posterUrl'] as String? ?? '';
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
    final epIdx = (item['episodeIndex'] as num?)?.toInt() ?? 0;

    return _MagneticBtn(
      onTap: () => _resumeWatching(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _doubleBezel(
            borderRadius: 14,
            outerPadding: 2,
            child: AspectRatio(
              aspectRatio: 0.65,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(
                    proxyImageUrl(poster),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF111114),
                      child: Icon(LucideIcons.film, color: Colors.white.withOpacity(0.15), size: 20),
                    ),
                  ),
                  if (progress >= 0.9)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.accent.withOpacity(0.4), width: 1),
                        ),
                        child: Icon(LucideIcons.check, color: AppTheme.accent, size: 11),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
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
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            'E${epIdx + 1} · ${(progress * 100).round()}%',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ── Watchlist ─────────────────────────────────────────────────────

  Widget _buildWatchlist(ResponsiveLayout layout) {
    final cols = layout.isPhone ? 3 : 5;
    final tileW = (layout.width - layout.pagePadding * 2 - 14 * (cols - 1)) / cols;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 56, layout.pagePadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'SAVED',
              style: TextStyle(
                color: AppTheme.accent.withOpacity(0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'My List',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 24),
          if (_favouriteIds.isEmpty)
            _emptyState(LucideIcons.bookmark, 'Your list is empty', 'Add shows to your list to watch later')
          else
            Wrap(
              spacing: 14,
              runSpacing: 20,
              children: List.generate(_favouriteIds.length, (i) {
                final tmdb = i < _favouriteTmdb.length ? _favouriteTmdb[i] : null;
                return SizedBox(width: tileW, child: _watchlistCard(_favouriteIds[i], tmdb));
              }),
            ),
        ],
      ),
    );
  }

  Widget _watchlistCard(String contentId, TmdbResult? tmdb) {
    return _MagneticBtn(
      onTap: () {
        if (tmdb != null) {
          ApiService().matchTmdbToProvider(tmdb).then((content) {
            if (content != null && mounted) DetailPage.show(context, content, initialTmdb: tmdb);
          });
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _doubleBezel(
            borderRadius: 14,
            outerPadding: 2,
            child: AspectRatio(
              aspectRatio: 0.65,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(
                    proxyImageUrl(tmdb?.posterUrl ?? ''),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF111114),
                      child: Icon(LucideIcons.film, color: Colors.white.withOpacity(0.15), size: 20),
                    ),
                  ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accent.withOpacity(0.4), width: 1),
                      ),
                      child: Icon(LucideIcons.bookmark, color: AppTheme.accent, size: 11),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tmdb?.englishTitle ?? contentId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            tmdb?.year ?? '',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.15), size: 22),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Magnetic Button — Hover + Press ────────────────────────────────

class _MagneticBtn extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _MagneticBtn({required this.child, this.onTap});

  @override
  State<_MagneticBtn> createState() => _MagneticBtnState();
}

class _MagneticBtnState extends State<_MagneticBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: _pressed
              ? (Matrix4.identity()..scale(0.97))
              : _hovered
                  ? (Matrix4.identity()..scale(1.03))
                  : Matrix4.identity(),
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
