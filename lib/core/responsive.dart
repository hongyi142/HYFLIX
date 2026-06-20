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
  double get heroHeight {
    if (isPhone) return 500;
    if (isTablet) return 620;
    return math.max(700.0, math.min(size.height * 0.8, 850.0));
  }
  double get heroContentWidth =>
      isPhone ? width - 64 : math.min(width * 0.5, 540);
  double get heroTitleSize => isPhone ? 28 : (isTablet ? 36 : 44);
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
