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
    with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _sweepComplete = false;

  @override
  void initState() {
    super.initState();

    _sweepController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _sweepController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_sweepComplete) {
        _sweepComplete = true;
        widget.onRevealComplete?.call();
        _pulseController.forward();
      }
    });

    _sweepController.forward();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: child,
        );
      },
      child: SizedBox(
        width: 300,
        height: 100,
        child: AnimatedBuilder(
          animation: _sweepController,
          builder: (context, _) {
            return CustomPaint(
              painter: _HyflixLogoPainter(
                sweepProgress: _sweepController.value,
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

    // Draw play button in the "H" crossbar once H is revealed
    if (painters.isNotEmpty) {
      final hRight = positions[0].dx + painters[0].width;
      if (hRight < sweepX) {
        _drawPlayButton(canvas, positions[0], painters[0], fontSize);
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

  void _drawPlayButton(Canvas canvas, Offset letterPos, TextPainter tp, double fontSize) {
    final hWidth = tp.width;
    final hHeight = tp.height;

    // Crossbar area: center vertical slice, ~40-65% of height
    final barLeft = letterPos.dx + hWidth * 0.28;
    final barRight = letterPos.dx + hWidth * 0.72;
    final barTop = letterPos.dy + hHeight * 0.38;
    final barBottom = letterPos.dy + hHeight * 0.62;

    final barWidth = barRight - barLeft;
    final barHeight = barBottom - barTop;

    // Scale triangle to fit within the crossbar
    final triHeight = barHeight * 0.6;
    final triWidth = barWidth * 0.45;
    final cx = barLeft + barWidth / 2;
    final cy = barTop + barHeight / 2;

    final path = Path()
      ..moveTo(cx - triWidth / 2, cy - triHeight / 2)
      ..lineTo(cx + triWidth / 2, cy)
      ..lineTo(cx - triWidth / 2, cy + triHeight / 2)
      ..close();

    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
  }

  @override
  bool shouldRepaint(_HyflixLogoPainter oldDelegate) =>
      oldDelegate.sweepProgress != sweepProgress;
}
