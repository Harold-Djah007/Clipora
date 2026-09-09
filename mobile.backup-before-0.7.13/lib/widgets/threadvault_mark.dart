import 'package:flutter/material.dart';

class ThreadVaultMark extends StatelessWidget {
  final double size;
  const ThreadVaultMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00D4FF), Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(size * .30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4FF).withOpacity(.24),
            blurRadius: size * .45,
            offset: Offset(0, size * .14),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white.withOpacity(.95), size: size * .58),
          Transform.translate(
            offset: Offset(size * .16, size * .16),
            child: Icon(Icons.arrow_downward_rounded, color: Colors.white, size: size * .30),
          ),
        ],
      ),
    );
  }
}
