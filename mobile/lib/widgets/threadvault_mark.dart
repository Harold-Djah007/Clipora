import 'dart:math' as math;
import 'package:flutter/material.dart';

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/brand/clipora_mark.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!widget.showGlow) return mark;

    return AnimatedBuilder(
      animation: _controller,
      child: mark,
      builder: (context, child) {
        final wave = .5 + (.5 * math.sin(_controller.value * math.pi * 2));
        return Transform.scale(
          scale: 1 + (wave * .026),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(.24 + (wave * .18)),
                  blurRadius: widget.size * (.34 + (wave * .20)),
                  spreadRadius: widget.size * (.02 + (wave * .03)),
                ),
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(.20 + (wave * .14)),
                  blurRadius: widget.size * (.54 + (wave * .22)),
                  spreadRadius: widget.size * .02,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}
