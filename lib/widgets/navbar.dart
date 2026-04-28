import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../core/theme.dart';
import '../pages/search_page.dart';
import '../pages/profile_page.dart';
import '../services/auth_service.dart';

class Navbar extends StatelessWidget {
  final bool isScrolled;
  const Navbar({super.key, this.isScrolled = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing64,
        vertical: AppTheme.spacing16,
      ),
      decoration: BoxDecoration(
        color: isScrolled ? AppTheme.background.withOpacity(0.7) : Colors.transparent,
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isScrolled ? 15 : 0,
            sigmaY: isScrolled ? 15 : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Logo only
              Row(
                children: [
                  Image.asset(
                    'assets/Logo.png',
                    height: 32,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(LucideIcons.image, color: Colors.white, size: 32),
                  ),
                ],
              ),

              // Center: Links
              Row(
                children: [
                  _NavLink(title: 'Home', isActive: true),
                  _NavLink(title: 'Movies'),
                  _NavLink(title: 'TV Shows'),
                  _NavLink(title: 'My List'),
                ],
              ),

              // Right: Icons & Profile
              Row(
                children: [
                  _NavIcon(
                icon: LucideIcons.search,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
              ),
                  const SizedBox(width: AppTheme.spacing16),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _NavIcon(icon: LucideIcons.bell),
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
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    ),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent,
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Center(
                        child: Text(
                          (AuthService.displayName?.isNotEmpty == true ? AuthService.displayName![0] : 'U').toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String title;
  final bool isActive;

  const _NavLink({required this.title, this.isActive = false});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: widget.isActive || _isHovered ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: IconButton(
        icon: Icon(
          widget.icon,
          color: _isHovered ? AppTheme.textPrimary : AppTheme.textSecondary,
          size: 20,
        ),
        onPressed: widget.onTap ?? () {},
        splashRadius: 24,
      ),
    );
  }
}
