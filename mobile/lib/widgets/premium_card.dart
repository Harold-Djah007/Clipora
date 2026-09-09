import 'package:flutter/material.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;
  final bool glow;
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFF12151C),
        border: Border.all(color: Colors.white.withOpacity(glow ? .14 : .08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class CliporaPage extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CliporaPage({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 112)});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xFF07090F),
        child: SafeArea(
          bottom: false,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class CliporaHeroCard extends StatelessWidget {
  final Widget child;
  const CliporaHeroCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF12151C),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class CliporaPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final double height;
  const CliporaPrimaryButton({super.key, required this.onPressed, required this.icon, required this.label, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? const Color(0xFF00C2C7) : const Color(0xFF2A313C),
          foregroundColor: enabled ? const Color(0xFF041216) : Colors.white54,
          disabledBackgroundColor: const Color(0xFF2A313C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

class CliporaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color? color;
  const CliporaPill({super.key, required this.icon, required this.label, this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF8BE9E0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(value!, style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

class CliporaSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const CliporaSectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.7)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(color: Color(0x99FFFFFF), height: 1.35, fontSize: 13.5)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
