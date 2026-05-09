import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
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

class _ProfilePageState extends State<ProfilePage> {
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

  @override
  void initState() {
    super.initState();
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
    final delta = scrollLeft ? -300.0 : 300.0;
    _continueScrollController.animateTo(
      (_continueScrollController.offset + delta).clamp(
        0,
        _continueScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _onScroll(); });

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
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.accent)));

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
    _continueScrollController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildHeader(layout),
                _buildStats(layout),
                if (_history.isNotEmpty) _buildContinueWatching(layout),
                _buildRecentlyWatched(layout),
                _buildWatchlist(layout),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _buildHeader(ResponsiveLayout layout) {
    final name = _profile?.displayName ?? 'User';
    final email = _profile?.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final memberSince = _profile?.createdAt != null
        ? 'Member since ${_fmtMonth(_profile!.createdAt!)}'
        : '';

    return Container(
      height: layout.isPhone ? 400 : 460,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network('https://picsum.photos/seed/profilehero/1920/1080',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: AppTheme.cardDark),
          ),
          Container(decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x400B0F14), Color(0x800B0F14), Color(0xE60B0F14), AppTheme.background],
            stops: [0.0, 0.3, 0.7, 1.0],
          ))),
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 18),
              ),
            ),
          ),
          // Settings button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: const Icon(LucideIcons.settings, color: Colors.white, size: 18),
              ),
            ),
          ),
          // Profile info
          Positioned(
            bottom: 32,
            left: layout.pagePadding,
            right: layout.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(colors: [AppTheme.accent, Color(0xFFCC0000)]),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
                      ),
                      child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800))),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('@${email.contains('@') ? email.split('@').first : name.toLowerCase().replaceAll(' ', '')}',
                          style: TextStyle(color: AppTheme.accent.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    )),
                  ],
                ),
                if (memberSince.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.calendar, color: AppTheme.accent, size: 13),
                      const SizedBox(width: 6),
                      Text(memberSince, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────

  Widget _buildStats(ResponsiveLayout layout) {
    final rate = (_completionRate * 100).round();
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final todayWd = now.weekday - 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 8, layout.pagePadding, 24),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _statTile(layout, LucideIcons.clock, 'Watch Time', _fmtTime(_profile?.watchTimeSeconds ?? 0)),
          _statTile(layout, LucideIcons.pieChart, 'Completion', '$rate% (${_showsCompleted}/${_totalShowsWatched})'),
          _statTile(layout, LucideIcons.clapperboard, 'Genre', 'Drama'),
          _statTile(layout, LucideIcons.flame, 'Streak', '$_watchStreak Days', trailing: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final active = i <= todayWd && i >= todayWd - _watchStreak + 1 && _watchStreak > 0;
              return Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppTheme.accent : Colors.white.withOpacity(0.06),
                  border: Border.all(color: active ? AppTheme.accent : Colors.white.withOpacity(0.1)),
                ),
                child: Center(child: active
                    ? const Icon(LucideIcons.check, color: Colors.white, size: 11)
                    : Text(days[i], style: TextStyle(color: AppTheme.textSecondary, fontSize: 9, fontWeight: FontWeight.w600))),
              );
            }),
          )),
        ],
      ),
    );
  }

  Widget _statTile(ResponsiveLayout layout, IconData icon, String label, String value, {Widget? trailing}) {
    final tileWidth = layout.isPhone
        ? (layout.width - layout.pagePadding * 2 - 12) / 2
        : (layout.width - layout.pagePadding * 2 - 12 * 3) / 4;

    return SizedBox(
      width: tileWidth,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: AppTheme.accent, size: 14),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            if (trailing != null) ...[const SizedBox(height: 8), trailing],
          ],
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
          padding: EdgeInsets.fromLTRB(layout.pagePadding, 8, layout.pagePadding, 8),
          child: Row(children: [
            const Expanded(child: Text('Continue Watching', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
            if (_canScrollLeft) _arrowBtn(LucideIcons.chevronLeft, () => _scrollContinue(true)),
            if (_canScrollRight) _arrowBtn(LucideIcons.chevronRight, () => _scrollContinue(false)),
          ]),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: layout.isPhone ? 190 : 220,
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

  Widget _arrowBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _continueCard(Map<String, dynamic> item, double cardW) {
    final title = item['title'] as String? ?? '';
    final poster = item['posterUrl'] as String? ?? '';
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
    final epIdx = (item['episodeIndex'] as num?)?.toInt() ?? 0;
    final posSec = (item['positionSeconds'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => _resumeWatching(item),
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Container(
              width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(poster, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppTheme.cardLight, child: const Center(child: Icon(LucideIcons.film, color: AppTheme.textSecondary)))),
                  Container(decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                  ))),
                  const Center(child: Icon(LucideIcons.play, color: Colors.white, size: 28)),
                  Positioned(top: 8, left: 8, child: _badge('E${epIdx + 1}')),
                  Positioned(top: 8, right: 8, child: _badge(_fmtTime(posSec))),
                  Positioned(bottom: 0, left: 0, right: 0, child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  )),
                ]),
              ),
            )),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${(progress * 100).round()}%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // ── Recently Watched ──────────────────────────────────────────────

  Widget _buildRecentlyWatched(ResponsiveLayout layout) {
    final items = _history.take(20).toList();
    final cols = layout.isPhone ? 3 : 6;
    final tileW = (layout.width - layout.pagePadding * 2 - 20 * 2 - 10 * (cols - 1)) / cols;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 24, layout.pagePadding, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Recently Watched', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('No watch history yet', style: TextStyle(color: AppTheme.textSecondary))),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: items.map((item) => SizedBox(width: tileW, child: _recentCard(item))).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recentCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? '';
    final poster = item['posterUrl'] as String? ?? '';
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;
    final epIdx = (item['episodeIndex'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () => _resumeWatching(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 0.65,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(poster, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppTheme.cardLight, child: const Icon(LucideIcons.film, color: AppTheme.textSecondary))),
                  Positioned(top: 5, left: 5, child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.check, color: Colors.white, size: 9),
                  )),
                  Positioned(bottom: 0, left: 0, right: 0, child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  )),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('E${epIdx + 1} · ${(progress * 100).round()}%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  // ── Watchlist ─────────────────────────────────────────────────────

  Widget _buildWatchlist(ResponsiveLayout layout) {
    final cols = layout.isPhone ? 3 : 4;
    final tileW = (layout.width - layout.pagePadding * 2 - 20 * 2 - 10 * (cols - 1)) / cols;

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pagePadding, 24, layout.pagePadding, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Watchlist', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (_favouriteIds.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Your watchlist is empty', style: TextStyle(color: AppTheme.textSecondary))),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: List.generate(_favouriteIds.length, (i) {
                  final tmdb = i < _favouriteTmdb.length ? _favouriteTmdb[i] : null;
                  return SizedBox(width: tileW, child: _watchlistCard(_favouriteIds[i], tmdb));
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _watchlistCard(String contentId, TmdbResult? tmdb) {
    return GestureDetector(
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
          AspectRatio(
            aspectRatio: 0.65,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(tmdb?.posterUrl ?? '', fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: AppTheme.cardLight, child: const Icon(LucideIcons.film, color: AppTheme.textSecondary))),
                  Positioned(top: 5, right: 5, child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                    child: const Icon(LucideIcons.bookmark, color: AppTheme.accent, size: 9),
                  )),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(tmdb?.englishTitle ?? contentId, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(tmdb?.year ?? '', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
