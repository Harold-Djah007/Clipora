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
          colors: [Color(0xFF8B5CF6), Color(0xFF4F46E5)],
        ),
        borderRadius: BorderRadius.circular(size * .26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(.30),
            blurRadius: size * .35,
            offset: Offset(0, size * .12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.download_rounded,
        color: Colors.white,
        size: size * .56,
      ),
    );
  }
}
