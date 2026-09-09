import 'dart:math' as math;
import 'package:flutter/material.dart';

class CliporaLaunchScreen extends StatefulWidget {
  const CliporaLaunchScreen({super.key});

  @override
  State<CliporaLaunchScreen> createState() => _CliporaLaunchScreenState();
}

class _CliporaLaunchScreenState extends State<CliporaLaunchScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final p = Curves.easeInOutCubic.transform(_controller.value);
          final markOpacity = ((p - .42) / .28).clamp(0.0, 1.0);
          final textOpacity = ((p - .62) / .26).clamp(0.0, 1.0);
          final scale = .86 + (.14 * Curves.easeOutBack.transform(markOpacity.clamp(0.0, 1.0)));
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF010309)),
              CustomPaint(painter: _TwistedRopeInflowPainter(progress: p)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: markOpacity,
                      child: Transform.scale(
                        scale: scale,
                        child: Image.asset(
                          'assets/brand/clipora_mark_3d.png',
                          width: 216,
                          height: 216,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: textOpacity,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (rect) => const LinearGradient(
                              colors: [Color(0xFF5CE1FF), Color(0xFFFFFFFF), Color(0xFFFF7A3D)],
                            ).createShader(rect),
                            child: const Text(
                              'Clipora',
                              style: TextStyle(
                                fontSize: 38,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'save • share • keep',
                            style: TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 12,
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TwistedRopeInflowPainter extends CustomPainter {
  final double progress;
  const _TwistedRopeInflowPainter({required this.progress});

  static const _ropes = <(Color, Color, Color)>[
    (Color(0xFF00F2EA), Color(0xFF1877F2), Color(0xFFFFFFFF)),
    (Color(0xFFFF0050), Color(0xFFFA7E1E), Color(0xFFFFFC00)),
    (Color(0xFF1877F2), Color(0xFF00F2EA), Color(0xFF111111)),
    (Color(0xFFE1306C), Color(0xFFFF0050), Color(0xFFFFFFFF)),
    (Color(0xFFFFFC00), Color(0xFFFA7E1E), Color(0xFF111111)),
    (Color(0xFF00F2EA), Color(0xFFFF0050), Color(0xFF1877F2)),
    (Color(0xFFFFFFFF), Color(0xFF00F2EA), Color(0xFF111111)),
    (Color(0xFFFA7E1E), Color(0xFFE1306C), Color(0xFFFFFC00)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reach = math.max(size.width, size.height) * .72;
    final fadeOut = progress > .72 ? (1 - ((progress - .72) / .22)).clamp(0.0, 1.0) : 1.0;

    for (var i = 0; i < _ropes.length; i++) {
      final delay = i * .045;
      final travel = ((progress - delay) / .58).clamp(0.0, 1.0);
      if (travel <= 0) continue;
      final eased = Curves.easeInOutCubic.transform(travel);
      final startAngle = (math.pi * 2 * i / _ropes.length) - .4;
      final twist = eased * 2.6;
      final start = Offset(
        center.dx + math.cos(startAngle) * reach,
        center.dy + math.sin(startAngle) * reach,
      );
      final end = Offset(
        center.dx + math.cos(startAngle + 2.15 + twist * .15) * 58,
        center.dy + math.sin(startAngle + 2.15 + twist * .15) * 58,
      );
      final control = Offset(
        center.dx + math.cos(startAngle + 1.05 + twist * .35) * (reach * (1 - eased * .62)),
        center.dy + math.sin(startAngle + 1.05 + twist * .35) * (reach * (1 - eased * .62)),
      );
      final spine = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      _drawTwistedRope(canvas, spine, _ropes[i], eased, fadeOut);
    }
  }

  void _drawTwistedRope(Canvas canvas, Path spine, (Color, Color, Color) colors, double travel, double fadeOut) {
    final metrics = spine.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final drawn = metric.length * travel;
    if (drawn <= 4) return;

    const samples = 56;
    final strands = [Path(), Path(), Path()];
    final palette = [colors.$1, colors.$2, colors.$3];

    for (var s = 0; s <= samples; s++) {
      final t = s / samples;
      final distance = drawn * t;
      final tangent = metric.getTangentForOffset(distance);
      if (tangent == null) continue;
      final vector = tangent.vector;
      final length = vector.distance;
      if (length == 0) continue;
      final nx = -vector.dy / length;
      final ny = vector.dx / length;
      final phase = t * math.pi * 10;
      const amp = 5.4;
      for (var k = 0; k < 3; k++) {
        final offset = math.sin(phase + k * 2.094) * amp;
        final point = Offset(tangent.position.dx + nx * offset, tangent.position.dy + ny * offset);
        if (s == 0) {
          strands[k].moveTo(point.dx, point.dy);
        } else {
          strands[k].lineTo(point.dx, point.dy);
        }
      }
    }

    final fade = (travel < .1 ? travel / .1 : 1.0) * fadeOut;
    for (var k = 0; k < 3; k++) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 7
        ..color = palette[k].withOpacity(.16 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawPath(strands[k], glow);
      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = k == 2 ? 2.1 : 2.6
        ..color = palette[k].withOpacity((.82 - k * .08) * fade);
      canvas.drawPath(strands[k], core);
    }
  }

  @override
  bool shouldRepaint(covariant _TwistedRopeInflowPainter oldDelegate) => oldDelegate.progress != progress;
}
