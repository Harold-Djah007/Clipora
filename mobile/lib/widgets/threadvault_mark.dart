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
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * .24),
      child: Image.asset(
        'assets/brand/clipora_mark_3d.png',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
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
