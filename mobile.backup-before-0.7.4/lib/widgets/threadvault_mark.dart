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
        borderRadius: BorderRadius.circular(size * .26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(.30),
            blurRadius: size * .35,
            offset: Offset(0, size * .12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/brand/threadvault_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
