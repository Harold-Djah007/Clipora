import 'package:flutter/material.dart';

class ThreadVaultMark extends StatelessWidget {
  final double size;
  final bool showGlow;
  const ThreadVaultMark({super.key, this.size = 48, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/brand/clipora_mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!showGlow) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(.32),
            blurRadius: size * .42,
            spreadRadius: size * .04,
          ),
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(.28),
            blurRadius: size * .58,
            spreadRadius: size * .02,
          ),
        ],
      ),
      child: mark,
    );
  }
}
