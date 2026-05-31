import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../pages/search_page.dart';
import '../pages/profile_page.dart';
import '../services/auth_service.dart';
import '../pages/browse_page.dart';
import '../pages/my_list_page.dart';

class Navbar extends StatelessWidget {
  final bool isScrolled;
  const Navbar({super.key, this.isScrolled = false});

  @override
  Widget build(BuildContext context) {
    final layout = ResponsiveLayout.of(context);
    final horizontalMargin = layout.isPhone
        ? 12.0
        : layout.isTablet
            ? 24.0
            : 48.0;
    final radius = layout.isPhone ? 14.0 : 18.0;
    final topPadding = MediaQuery.of(context).padding.top;
    final topMargin = topPadding + (layout.isPhone ? 10 : 14);
    return Container(
      margin: EdgeInsets.fromLTRB(
        horizontalMargin,
        topMargin,
        horizontalMargin,
        0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isScrolled ? 20 : 10,
            sigmaY: isScrolled ? 20 : 10,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: layout.isPhone ? 16 : layout.navHorizontalPadding,
              vertical: layout.isPhone ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: Color.fromRGBO(14, 18, 24, isScrolled ? 0.92 : 0.65),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withOpacity(isScrolled ? 0.12 : 0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isScrolled ? 0.4 : 0.2),
                  blurRadius: isScrolled ? 24 : 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: layout.isPhone
                ? _buildMobileNavbar(context)
                : _buildDesktopNavbar(context),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopNavbar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Image.asset(
          'assets/Logo.png',
          height: 28,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(LucideIcons.image, color: Colors.white, size: 28),
        ),
        Row(
          children: [
            _NavLink(title: 'Home', isActive: true),
            _NavLink(title: 'Movies', onTap: () => _openMovies(context)),
            _NavLink(title: 'TV Shows', onTap: () => _openTvShows(context)),
            _NavLink(title: 'Animation', onTap: () => _openAnimation(context)),
            _NavLink(title: 'My List', onTap: () => _openMyList(context)),
          ],
        ),
        Row(
          children: [
            _NavIcon(
              icon: LucideIcons.search,
              onTap: () => _openSearch(context),
            ),
            const SizedBox(width: 12),
            _ProfileAvatar(onTap: () => _openProfile(context), size: 34),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileNavbar(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => _showMobileMenu(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(LucideIcons.menu, color: Colors.white, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/Logo.png',
              height: 26,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(LucideIcons.image, color: Colors.white, size: 26),
            ),
          ),
        ),
        _NavIcon(icon: LucideIcons.search, onTap: () => _openSearch(context)),
        const SizedBox(width: 6),
        _ProfileAvatar(onTap: () => _openProfile(context), size: 36),
      ],
    );
  }

  void _showMobileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MobileMenuItem(
                  label: 'Home',
                  icon: LucideIcons.home,
                  onTap: () => Navigator.pop(context),
                ),
                _MobileMenuItem(
                  label: 'Movies',
                  icon: LucideIcons.clapperboard,
                  onTap: () {
                    Navigator.pop(context);
                    _openMovies(context);
                  },
                ),
                _MobileMenuItem(
                  label: 'TV Shows',
                  icon: LucideIcons.tv,
                  onTap: () {
                    Navigator.pop(context);
                    _openTvShows(context);
                  },
                ),
                _MobileMenuItem(
                  label: 'Animation',
                  icon: LucideIcons.sparkles,
                  onTap: () {
                    Navigator.pop(context);
                    _openAnimation(context);
                  },
                ),
                _MobileMenuItem(
                  label: 'My List',
                  icon: LucideIcons.listVideo,
                  onTap: () {
                    Navigator.pop(context);
                    _openMyList(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  void _openMyList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyListPage()),
    );
  }

  void _openMovies(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrowsePage(
          title: 'Movies',
          mediaType: 'movie',
          genres: [
            FilterOption('All Genres', ''),
            FilterOption('Action', '28'),
            FilterOption('Comedy', '35'),
            FilterOption('Romance', '10749'),
            FilterOption('Sci-Fi', '878'),
            FilterOption('Horror', '27'),
            FilterOption('Drama', '18'),
            FilterOption('Thriller', '53'),
            FilterOption('Adventure', '12'),
            FilterOption('Fantasy', '14'),
            FilterOption('Crime', '80'),
            FilterOption('Mystery', '9648'),
          ],
        ),
      ),
    );
  }

  void _openTvShows(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrowsePage(
          title: 'TV Shows',
          mediaType: 'tv',
          genres: [
            FilterOption('All Genres', ''),
            FilterOption('Drama', '18'),
            FilterOption('Comedy', '35'),
            FilterOption('Crime', '80'),
            FilterOption('Sci-Fi & Fantasy', '10765'),
            FilterOption('Action & Adventure', '10759'),
            FilterOption('Mystery', '9648'),
            FilterOption('War & Politics', '10768'),
          ],
          languages: [
            FilterOption('All', ''),
            FilterOption('Korean', 'ko'),
            FilterOption('Chinese', 'zh'),
            FilterOption('Japanese', 'ja'),
            FilterOption('Western', 'en'),
            FilterOption('Thai', 'th'),
          ],
        ),
      ),
    );
  }

  void _openAnimation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrowsePage(
          title: 'Animation',
          mediaType: 'tv',
          genres: [
            FilterOption('All Animation', '16'),
          ],
          languages: [
            FilterOption('All', ''),
            FilterOption('Japanese Anime', 'ja'),
            FilterOption('Chinese Donghua', 'zh'),
            FilterOption('Other', 'other'),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const _ProfileAvatar({required this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (hasFocus) { /* Optional: add focus ring */ },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent,
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
          ),
          child: Center(
            child: Text(
              (AuthService.displayName?.isNotEmpty == true
                      ? AuthService.displayName![0]
                      : 'U')
                  .toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMenuItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _MobileMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      contentPadding: EdgeInsets.zero,
      horizontalTitleGap: 12,
    );
  }
}

class _NavLink extends StatefulWidget {
  final String title;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavLink({required this.title, this.isActive = false, this.onTap});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (hasFocus) => setState(() => _isHovered = hasFocus),
      onShowHoverHighlight: (hasHover) => setState(() => _isHovered = hasHover),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            if (widget.onTap != null) widget.onTap!();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: widget.isActive || _isHovered
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: widget.isActive
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
                child: Text(widget.title),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: widget.isActive ? 24 : (_isHovered ? 24 : 0),
                color: AppTheme.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _NavIcon({required this.icon, this.onTap});

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (hasFocus) => setState(() => _isHovered = hasFocus),
      onShowHoverHighlight: (hasHover) => setState(() => _isHovered = hasHover),
      child: IconButton(
        icon: Icon(
          widget.icon,
          color: _isHovered ? AppTheme.textPrimary : AppTheme.textSecondary,
          size: 20,
        ),
        onPressed: widget.onTap ?? () {},
        splashRadius: 24,
        focusColor: Colors.white24,
      ),
    );
  }
}
