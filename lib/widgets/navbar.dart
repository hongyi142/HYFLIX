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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(
        horizontal: layout.navHorizontalPadding,
        vertical: layout.isPhone ? 12 : AppTheme.spacing16,
      ),
      decoration: BoxDecoration(
        color: isScrolled
            ? AppTheme.background.withOpacity(0.7)
            : Colors.transparent,
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isScrolled ? 15 : 0,
            sigmaY: isScrolled ? 15 : 0,
          ),
          child: layout.isPhone
              ? _buildMobileNavbar(context)
              : _buildDesktopNavbar(context),
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
          height: 32,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(LucideIcons.image, color: Colors.white, size: 32),
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
            const SizedBox(width: AppTheme.spacing16),
            Stack(
              clipBehavior: Clip.none,
              children: [
                const _NavIcon(icon: LucideIcons.bell),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppTheme.spacing16),
            _ProfileAvatar(onTap: () => _openProfile(context)),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(LucideIcons.menu, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/Logo.png',
              height: 28,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(LucideIcons.image, color: Colors.white, size: 28),
            ),
          ),
        ),
        _NavIcon(icon: LucideIcons.search, onTap: () => _openSearch(context)),
        const SizedBox(width: 6),
        _ProfileAvatar(onTap: () => _openProfile(context), size: 38),
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
  }

  void _openTvShows(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrowsePage(
          title: 'TV Shows',
          baseTypeId: 2,
          subTypes: [
            FilterOption('All TV Shows', '2'),
            FilterOption('Chinese Drama', '12'),
            FilterOption('Hong Kong/Macau', '13'),
            FilterOption('Japanese', '14'),
            FilterOption('Western', '15'),
            FilterOption('Taiwanese', '16'),
            FilterOption('Thai', '17'),
            FilterOption('Korean', '18'),
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
          baseTypeId: 4,
          subTypes: [
            FilterOption('All Animation', '4'),
            FilterOption('Anime Movies', '20'),
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
