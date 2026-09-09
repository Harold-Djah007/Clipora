import 'package:flutter/material.dart';

import 'clipora_rope_logo.dart';

/// Clipora mark used across the app. Keep this widget name so screens do not need to change.
class ThreadVaultMark extends StatelessWidget {
  final double size;
  final bool showGlow;

  const ThreadVaultMark({super.key, this.size = 48, this.showGlow = true});

  @override
  Widget build(BuildContext context) {
    return CliporaRopeLogo(
      size: size,
      showGlow: showGlow,
    );
  }
}
