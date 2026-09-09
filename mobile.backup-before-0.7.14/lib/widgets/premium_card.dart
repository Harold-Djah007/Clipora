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
    final radius = borderRadius ?? BorderRadius.circular(28);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xE61A2A58),
            Color(0xD7111833),
            Color(0xD80B1022),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(.10)),
        boxShadow: [
          const BoxShadow(blurRadius: 24, offset: Offset(0, 14), color: Color(0x66000000)),
          if (glow)
            BoxShadow(
              blurRadius: 34,
              spreadRadius: -12,
              offset: const Offset(0, 8),
              color: const Color(0xFF00D4FF).withOpacity(.35),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -75,
            child: _Orb(size: 150, color: const Color(0xFF00D4FF).withOpacity(.17)),
          ),
          Positioned(
            left: -80,
            bottom: -90,
            child: _Orb(size: 160, color: const Color(0xFF8B5CF6).withOpacity(.18)),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class CliporaPage extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const CliporaPage({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 110)});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020716), Color(0xFF061A35), Color(0xFF090A1F), Color(0xFF160B37)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(left: -100, top: -130, child: _Orb(size: 260, color: Color(0x4427E8FF))),
          const Positioned(right: -120, top: 120, child: _Orb(size: 240, color: Color(0x333B82F6))),
          const Positioned(left: 120, bottom: -140, child: _Orb(size: 260, color: Color(0x338B5CF6))),
          SafeArea(
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF113A8C), Color(0xFF0B1B57), Color(0xFF4C1D95)],
        ),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(blurRadius: 42, spreadRadius: -18, offset: Offset(0, 24), color: Color(0xFF0EA5E9)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(right: -52, top: -70, child: _Orb(size: 165, color: Colors.cyanAccent.withOpacity(.35))),
          Positioned(left: -70, bottom: -80, child: _Orb(size: 180, color: Colors.purpleAccent.withOpacity(.30))),
          Padding(padding: const EdgeInsets.all(22), child: child),
        ],
      ),
    );
  }
}

class CliporaPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final double height;
  const CliporaPrimaryButton({super.key, required this.onPressed, required this.icon, required this.label, this.height = 58});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF06B6D4)]),
          boxShadow: enabled
              ? [BoxShadow(color: const Color(0xFF06B6D4).withOpacity(.30), blurRadius: 24, offset: const Offset(0, 10))]
              : null,
        ),
        child: SizedBox(
          height: height,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: Colors.white)),
                ],
              ),
            ),
          ),
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
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        if (value != null) ...[
          const SizedBox(width: 5),
          Text(value!, style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600)),
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
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.6)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: const TextStyle(color: Colors.white60, height: 1.25)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: size * .35, spreadRadius: size * .08)],
      ),
    );
  }
}
