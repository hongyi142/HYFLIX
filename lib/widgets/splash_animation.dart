import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/theme.dart';

class SplashAnimation extends StatefulWidget {
  final VoidCallback? onRevealComplete;

  const SplashAnimation({super.key, this.onRevealComplete});

  @override
  State<SplashAnimation> createState() => _SplashAnimationState();
}

class _SplashAnimationState extends State<SplashAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _entranceScale;
  late Animation<double> _entranceOpacity;
  late Animation<double> _sweepProgress;
  late Animation<double> _zoomScale;
  late Animation<double> _zoomOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _entranceScale = Tween<double>(begin: 0.7, end: 1.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    _sweepProgress = Tween<double>(begin: -0.15, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeInOut),
      ),
    );

    _zoomScale = Tween<double>(begin: 1.0, end: 3.5).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.75, 1.0, curve: Curves.easeInQuint),
      ),
    );

    _zoomOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.78, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onRevealComplete?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _entranceScale.value * _zoomScale.value;
        final opacity = _entranceOpacity.value * _zoomOpacity.value;

        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: 320,
        height: 120,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _HyflixLogoPainter(
                sweepProgress: _sweepProgress.value,
                accentColor: AppTheme.accent,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HyflixLogoPainter extends CustomPainter {
  final double sweepProgress;
  final Color accentColor;

  static const String _text = 'HYFLIX';
  static const double _letterSpacing = 4.0;

  // Cached layout
  List<TextPainter>? _cachedPainters;
  List<Offset>? _cachedPositions;
  Size? _cachedSize;

  _HyflixLogoPainter({
    required this.sweepProgress,
    required this.accentColor,
  });

  void _layout(Size size) {
    if (_cachedSize == size && _cachedPainters != null) return;

    final fontSize = size.height * 0.48;
    final painters = <TextPainter>[];
    final positions = <Offset>[];

    // Measure each letter
    double totalWidth = 0;
    for (int i = 0; i < _text.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: _text[i],
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: _letterSpacing,
            color: accentColor,
            fontFamily: 'SFPro',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painters.add(tp);
      totalWidth += tp.width + (i < _text.length - 1 ? _letterSpacing : 0);
    }

    // Center the text
    double x = (size.width - totalWidth) / 2;
    final y = (size.height - fontSize) / 2;
    for (int i = 0; i < painters.length; i++) {
      positions.add(Offset(x, y));
      x += painters[i].width + _letterSpacing;
    }

    _cachedPainters = painters;
    _cachedPositions = positions;
    _cachedSize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layout(size);
    final painters = _cachedPainters!;
    final positions = _cachedPositions!;
    final fontSize = size.height * 0.48;

    // Calculate total text bounds
    final textLeft = positions.first.dx;
    final textRight = positions.last.dx + painters.last.width;
    final textWidth = textRight - textLeft;

    // Sweep position with overshoot for the glow
    final overshoot = fontSize * 0.8;
    final sweepX = textLeft - overshoot + (textWidth + overshoot * 2) * sweepProgress;

    // Pass 1: Draw revealed letters (full red)
    for (int i = 0; i < _text.length; i++) {
      final letterRight = positions[i].dx + painters[i].width;
      if (letterRight < sweepX - overshoot * 0.3) {
        painters[i].paint(canvas, positions[i]);
      }
    }

    // Pass 2: Draw the sweep glow
    if (sweepProgress > 0.02 && sweepProgress < 0.98) {
      _drawSweepGlow(canvas, size, sweepX, fontSize);
    }

    // Pass 3: Draw letters at sweep edge with clipping and bright tint
    for (int i = 0; i < _text.length; i++) {
      final letterLeft = positions[i].dx;
      final letterRight = letterLeft + painters[i].width;
      final inSweep = letterLeft < sweepX && letterRight > sweepX - overshoot * 0.3;
      if (inSweep) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, sweepX, size.height));
        painters[i].paint(
          canvas,
          positions[i],
        );
        canvas.restore();
      }
    }

  }

  void _drawSweepGlow(Canvas canvas, Size size, double sweepX, double fontSize) {
    final glowWidth = fontSize * 1.2;
    final glowRect = Rect.fromCenter(
      center: Offset(sweepX, size.height / 2),
      width: glowWidth,
      height: size.height * 1.2,
    );

    // Soft ambient glow
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(sweepX, size.height / 2),
        glowWidth,
        [
          accentColor.withOpacity(0.15),
          accentColor.withOpacity(0.05),
          Colors.transparent,
        ],
        [0.0, 0.5, 1.0],
      );
    canvas.drawRect(glowRect.inflate(fontSize), glowPaint);

    // Sharp beam at the sweep edge
    final beamWidth = fontSize * 0.12;
    final beamRect = Rect.fromCenter(
      center: Offset(sweepX, size.height / 2),
      width: beamWidth,
      height: size.height,
    );
    final beamPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawRect(beamRect, beamPaint);

    // Bright core
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(beamRect, corePaint);
  }



  @override
  bool shouldRepaint(_HyflixLogoPainter oldDelegate) =>
      oldDelegate.sweepProgress != sweepProgress;
}
