import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Clipora mark used across the app. Keep this widget name so screens do not need to change.
class ThreadVaultMark extends StatefulWidget {
  final double size;
  final bool showGlow;
  const ThreadVaultMark({super.key, this.size = 48, this.showGlow = true});

  @override
  State<ThreadVaultMark> createState() => _ThreadVaultMarkState();
}

class _ThreadVaultMarkState extends State<ThreadVaultMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(widget.size),
      painter: const _CliporaMarkPainter(),
    );
    if (!widget.showGlow) return mark;

    return AnimatedBuilder(
      animation: _controller,
      child: mark,
      builder: (context, child) {
        final wave = .5 + (.5 * math.sin(_controller.value * math.pi * 2));
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size * .24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F2EA).withOpacity(.16 + wave * .10),
                blurRadius: widget.size * .36,
              ),
              BoxShadow(
                color: const Color(0xFFFF0050).withOpacity(.10 + wave * .08),
                blurRadius: widget.size * .50,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

class _CliporaMarkPainter extends CustomPainter {
  const _CliporaMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final tile = RRect.fromRectAndRadius(
      Rect.fromCircle(center: center, radius: size.shortestSide * .46),
      Radius.circular(size.shortestSide * .24),
    );
    canvas.drawRRect(tile, Paint()..color = const Color(0xFF07111F));
    canvas.drawRRect(
      tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * .02
        ..color = Colors.white.withOpacity(.10),
    );

    final arc = Rect.fromCircle(center: center, radius: size.shortestSide * .27);
    const ribbons = <Color>[
      Color(0xFF00F2EA),
      Color(0xFFFF0050),
      Color(0xFF1877F2),
    ];
    for (var i = 0; i < ribbons.length; i++) {
      canvas.drawArc(
        arc.inflate(i * size.shortestSide * .012),
        math.pi * .58,
        math.pi * 1.68,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.shortestSide * (.11 - i * .018)
          ..color = ribbons[i].withOpacity(.92 - i * .12),
      );
    }

    final tri = Path()
      ..moveTo(center.dx - size.width * .02, center.dy - size.height * .10)
      ..lineTo(center.dx - size.width * .02, center.dy + size.height * .10)
      ..lineTo(center.dx + size.width * .13, center.dy)
      ..close();
    canvas.drawPath(tri, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _CliporaMarkPainter oldDelegate) => false;
}
