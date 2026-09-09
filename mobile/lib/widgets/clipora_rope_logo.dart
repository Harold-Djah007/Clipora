import 'dart:math' as math;

import 'package:flutter/material.dart';

class CliporaRopeLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final double progress;

  const CliporaRopeLogo({
    super.key,
    this.size = 96,
    this.showGlow = true,
    this.progress = 1,
  });

  @override
  Widget build(BuildContext context) {
    final child = CustomPaint(
      size: Size.square(size),
      painter: CliporaRopeLogoPainter(progress: progress.clamp(0.0, 1.0).toDouble()),
    );
    if (!showGlow) return child;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00F2EA).withOpacity(.18), blurRadius: size * .28),
          BoxShadow(color: const Color(0xFFFF2BD6).withOpacity(.18), blurRadius: size * .34),
          BoxShadow(color: const Color(0xFFFFB000).withOpacity(.10), blurRadius: size * .42),
        ],
      ),
      child: child,
    );
  }
}

class CliporaRopeLaunchAnimation extends StatelessWidget {
  final Animation<double> animation;

  const CliporaRopeLaunchAnimation({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = animation.value.clamp(0.0, 1.0).toDouble();
        final p = Curves.easeInOutCubic.transform(raw);
        final logoProgress = ((p - .26) / .58).clamp(0.0, 1.0).toDouble();
        final settle = Curves.easeOutBack.transform(((p - .64) / .30).clamp(0.0, 1.0).toDouble());
        final textOpacity = ((p - .72) / .20).clamp(0.0, 1.0).toDouble();
        final scale = .82 + (.18 * settle.clamp(0.0, 1.05));

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _RopeFinaleBackgroundPainter(progress: p)),
            CustomPaint(painter: _RopeInflowPainter(progress: p)),
            Center(
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 176,
                      height: 176,
                      child: CliporaRopeLogo(size: 176, progress: logoProgress),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: textOpacity,
                      child: Column(
                        children: const [
                          Text(
                            'Clipora',
                            style: TextStyle(
                              fontSize: 38,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.35,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'threads twist into saves',
                            style: TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 12,
                              letterSpacing: 2.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CliporaRopeLogoPainter extends CustomPainter {
  final double progress;

  const CliporaRopeLogoPainter({this.progress = 1});

  static const _ropeColors = <Color>[
    Color(0xFF00F2EA),
    Color(0xFF1877F2),
    Color(0xFFFFFFFF),
    Color(0xFF111827),
    Color(0xFFFF0050),
    Color(0xFFFF7A18),
    Color(0xFFFFD21E),
    Color(0xFFB026FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final center = size.center(Offset.zero);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: shortest * .92, height: shortest * .92),
      Radius.circular(shortest * .23),
    );
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF041120), Color(0xFF0B0D1A), Color(0xFF1A0730)],
      ).createShader(rrect.outerRect);
    canvas.drawRRect(rrect, bg);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * .018
        ..shader = const LinearGradient(
          colors: [Color(0xFF00F2EA), Color(0xFF1877F2), Color(0xFFFF2BD6), Color(0xFFFFB000)],
        ).createShader(rrect.outerRect),
    );

    final arcRect = Rect.fromCircle(center: center.translate(-shortest * .01, -shortest * .02), radius: shortest * .285);
    final sweep = math.pi * 1.68 * progress.clamp(0.0, 1.0);
    final start = math.pi * .58;
    if (sweep <= 0) return;

    final shadowPath = Path()..addArc(arcRect.inflate(shortest * .012), start, sweep);
    canvas.drawPath(
      shadowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = shortest * .20
        ..color = Colors.black.withOpacity(.36)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shortest * .035),
    );

    final width = shortest * .052;
    for (var i = 0; i < _ropeColors.length; i++) {
      final laneOffset = (i - (_ropeColors.length - 1) / 2) * width * .38;
      final path = Path()..addArc(arcRect.inflate(laneOffset), start + i * .042, math.max(0, sweep - i * .018));
      _RopePainter.drawRope(
        canvas,
        path,
        _ropeColors[i],
        strokeWidth: width,
        opacity: .95,
        fiberOpacity: .34,
        fiberSpacing: shortest * .052,
      );
    }

    final triProgress = ((progress - .76) / .20).clamp(0.0, 1.0).toDouble();
    if (triProgress <= 0) return;
    final tri = Path()
      ..moveTo(center.dx - shortest * .025, center.dy - shortest * .092)
      ..lineTo(center.dx - shortest * .025, center.dy + shortest * .092)
      ..lineTo(center.dx + shortest * .135, center.dy)
      ..close();
    canvas.drawPath(
      tri,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFF00F2EA), Color(0xFFFFD21E)],
        ).createShader(tri.getBounds())
        ..color = Colors.white.withOpacity(triProgress),
    );
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = shortest * .012
        ..color = Colors.white.withOpacity(.85 * triProgress),
    );
  }

  @override
  bool shouldRepaint(covariant CliporaRopeLogoPainter oldDelegate) => oldDelegate.progress != progress;
}

class _RopeFinaleBackgroundPainter extends CustomPainter {
  final double progress;

  const _RopeFinaleBackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.center,
          radius: .92,
          colors: [Color(0xFF111B34), Color(0xFF050812), Color(0xFF02030A)],
        ).createShader(rect),
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
      ..strokeWidth = 1.6;
    final center = size.center(Offset.zero);
    for (var i = 0; i < 5; i++) {
      final a = progress * math.pi * 2 + i * math.pi * .42;
      final r = size.shortestSide * (.28 + i * .06);
      final path = Path()
        ..moveTo(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r)
        ..quadraticBezierTo(
          center.dx + math.cos(a + .8) * r * .45,
          center.dy + math.sin(a + .8) * r * .45,
          center.dx + math.cos(a + 1.8) * r,
          center.dy + math.sin(a + 1.8) * r,
        );
      glow.color = [
        const Color(0xFF00F2EA),
        const Color(0xFFFF0050),
        const Color(0xFF1877F2),
        const Color(0xFFFFD21E),
        const Color(0xFFB026FF),
      ][i].withOpacity(.16);
      canvas.drawPath(path, glow);
    }
  }

  @override
  bool shouldRepaint(covariant _RopeFinaleBackgroundPainter oldDelegate) => oldDelegate.progress != progress;
}

class _RopeInflowPainter extends CustomPainter {
  final double progress;

  const _RopeInflowPainter({required this.progress});

  static const _specs = <_RopeSpec>[
    _RopeSpec(Color(0xFF00F2EA), -2.55, .15, 0.00),
    _RopeSpec(Color(0xFF1877F2), -1.92, .48, 0.05),
    _RopeSpec(Color(0xFFFFFFFF), -1.25, .82, 0.10),
    _RopeSpec(Color(0xFF111827), -0.55, 1.12, 0.15),
    _RopeSpec(Color(0xFFFF0050), .12, 1.48, 0.20),
    _RopeSpec(Color(0xFFFF7A18), .78, 1.82, 0.25),
    _RopeSpec(Color(0xFFFFD21E), 1.42, 2.18, 0.30),
    _RopeSpec(Color(0xFFB026FF), 2.18, 2.58, 0.35),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero).translate(0, -44);
    final reach = math.max(size.width, size.height) * .68;
    final cRadius = math.min(size.width, size.height) * .145;

    for (var i = 0; i < _specs.length; i++) {
      final spec = _specs[i];
      final local = ((progress - spec.delay) / .68).clamp(0.0, 1.0).toDouble();
      if (local <= 0) continue;
      final eased = Curves.easeInOutCubic.transform(local);
      final start = Offset(
        center.dx + math.cos(spec.startAngle) * reach,
        center.dy + math.sin(spec.startAngle) * reach,
      );
      final finishAngle = math.pi * .58 + spec.finishBias;
      final end = Offset(
        center.dx + math.cos(finishAngle) * cRadius,
        center.dy + math.sin(finishAngle) * cRadius,
      );
      final control1 = Offset(
        center.dx + math.cos(spec.startAngle + 1.15) * reach * .45,
        center.dy + math.sin(spec.startAngle + 1.15) * reach * .45,
      );
      final control2 = Offset(
        center.dx + math.cos(finishAngle - 1.35) * cRadius * 2.8,
        center.dy + math.sin(finishAngle - 1.35) * cRadius * 2.8,
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);

      final metrics = path.computeMetrics().toList(growable: false);
      if (metrics.isEmpty) continue;
      final metric = metrics.first;
      final head = metric.length * eased;
      final tail = math.max(0.0, head - metric.length * (.32 + .10 * math.sin(i + progress * math.pi)));
      final segment = metric.extractPath(tail, head);
      final fadeOut = progress > .82 ? (1 - ((progress - .82) / .18)).clamp(0.0, 1.0).toDouble() : 1.0;
      final opacity = (.30 + .70 * local) * fadeOut;

      _RopePainter.drawRope(
        canvas,
        segment,
        spec.color,
        strokeWidth: 8.5,
        opacity: opacity,
        fiberOpacity: .42,
        fiberSpacing: 15,
      );

      final tangent = metric.getTangentForOffset(head);
      if (tangent != null && fadeOut > 0) {
        canvas.drawCircle(
          tangent.position,
          6.5,
          Paint()
            ..color = spec.color.withOpacity(.34 * opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RopeInflowPainter oldDelegate) => oldDelegate.progress != progress;
}

class _RopePainter {
  static void drawRope(
    Canvas canvas,
    Path path,
    Color color, {
    required double strokeWidth,
    required double opacity,
    required double fiberOpacity,
    required double fiberSpacing,
  }) {
    if (opacity <= 0) return;

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth + 4
        ..color = Colors.black.withOpacity(.28 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth
        ..color = color.withOpacity(.92 * opacity),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(1.2, strokeWidth * .24)
        ..color = Colors.white.withOpacity(.38 * opacity),
    );

    final metrics = path.computeMetrics().toList(growable: false);
    final fiberPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, strokeWidth * .16)
      ..color = Colors.white.withOpacity(fiberOpacity * opacity);
    for (final metric in metrics) {
      for (var d = 0.0; d < metric.length; d += fiberSpacing) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        final vector = tangent.vector;
        final len = vector.distance;
        if (len == 0) continue;
        final dir = Offset(vector.dx / len, vector.dy / len);
        final normal = Offset(-dir.dy, dir.dx);
        final half = strokeWidth * .42;
        final skew = strokeWidth * .18;
        canvas.drawLine(
          tangent.position - normal * half + dir * skew,
          tangent.position + normal * half - dir * skew,
          fiberPaint,
        );
      }
    }
  }
}

class _RopeSpec {
  final Color color;
  final double startAngle;
  final double finishBias;
  final double delay;

  const _RopeSpec(this.color, this.startAngle, this.finishBias, this.delay);
}
