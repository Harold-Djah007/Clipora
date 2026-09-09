import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clipora's universal-social brand mark.
/// The same widget name is kept so the rest of the app does not need to change.
class ThreadVaultMark extends StatefulWidget {
  final double size;
  final bool showGlow;
  const ThreadVaultMark({super.key, this.size = 48, this.showGlow = true});

  @override
  State<ThreadVaultMark> createState() => _ThreadVaultMarkState();
}

class _ThreadVaultMarkState extends State<ThreadVaultMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _socialColors = <Color>[
    Color(0xFF00F2EA), // TikTok cyan
    Color(0xFFFF0050), // TikTok red / Pinterest red energy
    Color(0xFFFFFFFF), // X / Threads white stroke
    Color(0xFF000000), // X / Threads black depth
    Color(0xFFFEDA75), // Instagram / Snapchat yellow
    Color(0xFFFA7E1E), // Instagram orange
    Color(0xFFD62976), // Instagram pink
    Color(0xFF962FBF), // Instagram purple
    Color(0xFF1877F2), // Facebook blue
    Color(0xFF1DA1F2), // X/Twitter blue legacy
    Color(0xFFE60023), // Pinterest red
    Color(0xFFFFFC00), // Snapchat yellow
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
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
      builder: (context, _) {
        final wave = .5 + (.5 * math.sin(_controller.value * math.pi * 2));
        final mark = CustomPaint(
          size: Size.square(widget.size),
          painter: _SocialCliporaMarkPainter(progress: _controller.value, glow: widget.showGlow),
        );
        if (!widget.showGlow) return mark;
        return Transform.scale(
          scale: 1 + (wave * .022),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.size * .26),
              boxShadow: [
                BoxShadow(
                  color: _socialColors[0].withOpacity(.20 + (wave * .13)),
                  blurRadius: widget.size * .42,
                  spreadRadius: widget.size * .02,
                ),
                BoxShadow(
                  color: _socialColors[6].withOpacity(.18 + (wave * .12)),
                  blurRadius: widget.size * .56,
                  spreadRadius: widget.size * .02,
                ),
                BoxShadow(
                  color: _socialColors[8].withOpacity(.15 + (wave * .10)),
                  blurRadius: widget.size * .70,
                  spreadRadius: widget.size * .01,
                ),
              ],
            ),
            child: mark,
          ),
        );
      },
    );
  }
}

class _SocialCliporaMarkPainter extends CustomPainter {
  final double progress;
  final bool glow;
  const _SocialCliporaMarkPainter({required this.progress, required this.glow});

  static const socialColors = <Color>[
    Color(0xFF00F2EA), Color(0xFFFF0050), Color(0xFFFFFFFF), Color(0xFF050505),
    Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF),
    Color(0xFF1877F2), Color(0xFF1DA1F2), Color(0xFFE60023), Color(0xFFFFFC00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.shortestSide * .27);
    final rrect = RRect.fromRectAndRadius(rect.deflate(size.shortestSide * .04), radius);

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF030712), Color(0xFF07152F), Color(0xFF16051F), Color(0xFF020617)],
      ).createShader(rect);
    canvas.drawRRect(rrect, bg);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * .045
      ..shader = SweepGradient(colors: socialColors).createShader(rect);
    canvas.drawRRect(rrect, border);

    final center = size.center(Offset.zero);
    final arcRect = Rect.fromCircle(center: center, radius: size.shortestSide * .31);
    final wave = .5 + (.5 * math.sin(progress * math.pi * 2));

    if (glow) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * .27
        ..color = const Color(0xFF00F2EA).withOpacity(.13 + (.07 * wave))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * .12);
      canvas.drawArc(arcRect.inflate(size.shortestSide * .02), math.pi * .58, math.pi * 1.73, false, glowPaint);
    }

    for (var i = 0; i < socialColors.length; i++) {
      final lane = ((i - 5.5) * size.shortestSide * .006);
      final ribbon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * (.030 + ((i % 3) * .006))
        ..color = socialColors[i].withOpacity(i == 3 ? .38 : .74);
      canvas.drawArc(
        arcRect.inflate(lane),
        math.pi * (.58 + (i * .012)),
        math.pi * 1.70,
        false,
        ribbon,
      );
    }

    final cPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .155
      ..shader = SweepGradient(
        startAngle: .1 + progress,
        endAngle: math.pi * 2,
        colors: socialColors,
      ).createShader(arcRect.inflate(size.shortestSide * .10));
    canvas.drawArc(arcRect, math.pi * .61, math.pi * 1.67, false, cPaint);

    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .026
      ..color = Colors.white.withOpacity(.44);
    canvas.drawArc(arcRect.deflate(size.shortestSide * .065), math.pi * 1.09, math.pi * .38, false, shine);

    final tri = Path()
      ..moveTo(center.dx - size.width * .018, center.dy - size.height * .108)
      ..lineTo(center.dx - size.width * .018, center.dy + size.height * .108)
      ..lineTo(center.dx + size.width * .142, center.dy)
      ..close();
    final triGlow = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFF0050).withOpacity(.24)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * .075);
    canvas.drawPath(tri, triGlow);
    final triFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF00F2EA), Color(0xFF1877F2), Color(0xFFD62976), Color(0xFFFFFC00)],
      ).createShader(tri.getBounds());
    canvas.drawPath(tri, triFill);
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.shortestSide * .025
        ..color = Colors.white.withOpacity(.45),
    );
  }

  @override
  bool shouldRepaint(covariant _SocialCliporaMarkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.glow != glow;
}
