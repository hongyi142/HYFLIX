import 'dart:math' as math;

import 'package:flutter/material.dart';

class ResponsiveLayout {
  const ResponsiveLayout._(this.size);

  factory ResponsiveLayout.of(BuildContext context) {
    return ResponsiveLayout._(MediaQuery.of(context).size);
  }

  final Size size;

  static const double phoneBreakpoint = 720;
  static const double tabletBreakpoint = 1100;

  double get width => size.width;
  double get height => size.height;

  bool get isPhone => width < phoneBreakpoint;
  bool get isTablet => width >= phoneBreakpoint && width < tabletBreakpoint;
  bool get isDesktop => width >= tabletBreakpoint;
  bool get usesBottomNav => isPhone;
  bool get showDesktopNavLinks => !isPhone;
  bool get useWideDetailLayout => width >= 920;

  double get pagePadding => isPhone ? 16 : (isTablet ? 24 : 32);
  double get sectionGap => isPhone ? 32 : 48;
  double get navHorizontalPadding => isPhone ? 16 : (isTablet ? 24 : 64);
  double get topSafeSpacing => isPhone ? 88 : 60;

  /// True when the screen is in a wide-screen TV aspect ratio (≥ 16:9).
  /// Android TV / Apple TV boxes typically output 1920×1080 (ar = 1.78).
  bool get isTVAspect => !isPhone && (size.width / size.height) >= 1.7;

  double get heroHeight {
    if (isPhone) return 500;
    if (isTablet) return 620;

    // For large screens (TV / desktop), scale hero based on aspect ratio.
    // Wider screens (16:9 TV) show more horizontal content so the hero
    // should take up LESS vertical space so content shelves are visible below.
    final ar = size.width / size.height; // ~1.78 for 16:9, ~1.6 for 16:10
    // Map aspect ratio to a height fraction:
    //   ar ≤ 1.5  (3:2 monitor)        → 63% of screen height
    //   ar ~1.6   (16:10 monitor)      → 58% of screen height
    //   ar ~1.78  (16:9 TV / 1080p)   → 52% of screen height
    //   ar ≥ 2.0  (ultra-wide)         → 48% of screen height
    final fraction = (0.52 + (1.78 - ar.clamp(1.5, 2.0)) * 0.22)
        .clamp(0.48, 0.65);
    return math.max(360.0, math.min(size.height * fraction, 680.0));
  }

  double get heroContentWidth =>
      isPhone ? width - 64 : math.min(width * (isTVAspect ? 0.45 : 0.5), 560);
  double get heroTitleSize => isPhone ? 28 : (isTablet ? 36 : (isTVAspect ? 40 : 44));
  double get modalHorizontalPadding => isPhone ? 12 : (isTablet ? 32 : 100);
  double get modalVerticalPadding => isPhone ? 12 : 40;

  double get posterCardWidth => isPhone ? 128 : 150;
  double get landscapeCardWidth => isPhone ? 240 : (isTablet ? 260 : 280);
  double get sectionTitleSize => isPhone ? 18 : 22;

  double gridMaxExtent({
    double compact = 140,
    double tablet = 160,
    double desktop = 180,
  }) {
    if (isPhone) return compact;
    if (isTablet) return tablet;
    return desktop;
  }

  int gridCount({int compact = 3, int tablet = 4, int desktop = 6}) {
    if (isPhone) return compact;
    if (isTablet) return tablet;
    return desktop;
  }
}
