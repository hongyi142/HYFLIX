import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/tmdb_service.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _profile;
  List<Map<String, dynamic>> _history = [];
  List<String> _favouriteIds = [];
  bool _loading = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final profileData = await UserService.getProfile();
    final history = await UserService.getWatchHistory();
    final favs = await UserService.getFavouriteIds();

    if (mounted) {
      setState(() {
        if (profileData != null) {
          _profile = UserProfile.fromMap(AuthService.uid!, profileData);
        } else {
          // Fallback: build a profile from AuthService data when RTDB has no profile yet
          _profile = UserProfile(
            uid: AuthService.uid ?? '',
            email: AuthService.email ?? '',
            displayName: AuthService.displayName ?? '',
          );
        }
        _history = history;
        _favouriteIds = favs;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : CustomScrollView(
              slivers: [
                // ── Header with back button ─────────────────
                SliverToBoxAdapter(child: _buildHeader()),
                // ── Profile Info ────────────────────────────
                SliverToBoxAdapter(child: _buildProfileInfo()),
                // ── Stats ───────────────────────────────────
                SliverToBoxAdapter(child: _buildStats()),
                // ── Tabs ────────────────────────────────────
                SliverToBoxAdapter(child: _buildTabs()),
                // ── Content ─────────────────────────────────
                if (_selectedTab == 0)
                  _buildHistoryList()
                else
                  _buildFavouritesList(),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 20, 0),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Profile',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          // Settings
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))
                .then((_) => _loadData()),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(LucideIcons.settings, color: AppTheme.textSecondary, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          // Sign out
          GestureDetector(
            onTap: _signOut,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(LucideIcons.logOut, color: AppTheme.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo() {
    final email = _profile?.email ?? '';
    final displayName = _profile?.displayName ?? '';
    final username = displayName.isNotEmpty
        ? displayName
        : (email.contains('@') ? email.split('@').first : 'User');

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (username.isNotEmpty ? username[0] : 'U').toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${username.toLowerCase().replaceAll(' ', '')}',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Row(
        children: [
          _statCard(LucideIcons.clock, 'Watch Time', _formatTime(_profile?.watchTimeSeconds ?? 0)),
          const SizedBox(width: 12),
          _statCard(LucideIcons.heart, 'Favourites', '${_favouriteIds.length}'),
          const SizedBox(width: 12),
          _statCard(LucideIcons.history, 'Watched', '${_history.length}'),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.accent, size: 22),
            const SizedBox(height: 10),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Row(
        children: [
          _tabButton('Watch History', 0),
          const SizedBox(width: 10),
          _tabButton('Favourites', 1),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isActive = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accent : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isActive ? AppTheme.accent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text('No watch history yet', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _historyTile(_history[i]),
        childCount: _history.length,
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              item['posterUrl'] ?? '',
              width: 65, height: 90, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 65, height: 90,
                color: AppTheme.cardLight,
                child: const Icon(LucideIcons.film, color: AppTheme.textSecondary, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (item['progress'] as double?) ?? 0.0,
                    backgroundColor: AppTheme.cardLight,
                    color: AppTheme.accent,
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavouritesList() {
    if (_favouriteIds.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text('No favourites yet', style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 32),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.55,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _favouriteTile(_favouriteIds[i]),
          childCount: _favouriteIds.length,
        ),
      ),
    );
  }

  Widget _favouriteTile(String contentId) {
    return FutureBuilder<TmdbResult?>(
      future: TmdbService.search(contentId),
      builder: (context, snap) {
        final tmdb = snap.data;
        return Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  tmdb?.posterUrl ?? '',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.cardLight,
                    child: const Icon(LucideIcons.image, color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tmdb?.englishTitle ?? contentId,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
