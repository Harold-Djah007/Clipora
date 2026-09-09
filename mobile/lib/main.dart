import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app_state.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/history/history_screen.dart';
import 'features/session/session_screen.dart';
import 'features/settings/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const CliporaApp()));
}

class CliporaApp extends StatelessWidget {
  const CliporaApp({super.key});

  static const _cyan = Color(0xFF00F2EA);
  static const _pink = Color(0xFFFF0050);
  static const _blue = Color(0xFF1877F2);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _cyan,
      brightness: Brightness.dark,
      primary: _cyan,
      secondary: _pink,
      tertiary: _blue,
      surface: const Color(0xFF0A1024),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clipora',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF07090F),
        fontFamily: 'Roboto',
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: false),
        navigationBarTheme: NavigationBarThemeData(
          height: 68,
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: _cyan.withOpacity(.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                color: states.contains(WidgetState.selected) ? Colors.white : Colors.white54,
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: 22,
                color: states.contains(WidgetState.selected) ? _cyan : Colors.white54,
              )),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF161A22),
          hintStyle: const TextStyle(color: Colors.white38),
          labelStyle: const TextStyle(color: Colors.white70),
          helperStyle: const TextStyle(color: Color(0x73FFFFFF)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Color(0xFF00C2C7), width: 1.2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            side: BorderSide(color: Colors.white.withOpacity(.18)),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF22D3EE),
          thumbColor: const Color(0xFF22D3EE),
          inactiveTrackColor: Colors.white.withOpacity(.12),
          overlayColor: const Color(0xFF22D3EE).withOpacity(.15),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF67E8F9) : Colors.white70),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0xFF2563EB).withOpacity(.65) : Colors.white24),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFF0B1227),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0B1227),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const CliporaLaunchGate(),
    );
  }
}

class CliporaLaunchGate extends StatefulWidget {
  const CliporaLaunchGate({super.key});

  @override
  State<CliporaLaunchGate> createState() => _CliporaLaunchGateState();
}

class _CliporaLaunchGateState extends State<CliporaLaunchGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _ready ? const HomeShell(key: ValueKey('home')) : const CliporaLaunchScreen(key: ValueKey('launch')),
    );
  }
}

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020716),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final p = Curves.easeInOutCubic.transform(_controller.value);
          final textOpacity = ((p - .62) / .28).clamp(0.0, 1.0).toDouble();
          final scale = .94 + (.06 * Curves.easeOutCubic.transform(p));
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _SocialThreadInflowPainter(progress: p)),
              ),
              Center(
                child: Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 168,
                        height: 168,
                        child: CustomPaint(painter: _CliporaMarkPainter(progress: p)),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: textOpacity,
                        child: const Column(
                          children: [
                            Text(
                              'Clipora',
                              style: TextStyle(fontSize: 36, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.2),
                            ),
                            SizedBox(height: 8),
                            Text(
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
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SocialThreadInflowPainter extends CustomPainter {
  final double progress;
  const _SocialThreadInflowPainter({required this.progress});

  static const _threads = <Color>[
    Color(0xFF00F2EA),
    Color(0xFFFF0050),
    Color(0xFF1877F2),
    Color(0xFFFA7E1E),
    Color(0xFF962FBF),
    Color(0xFFFFFC00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final reach = math.max(size.width, size.height) * .62;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < _threads.length; i++) {
      final color = _threads[i];
      final delay = i * .07;
      final travel = ((progress - delay) / .72).clamp(0.0, 1.0).toDouble();
      if (travel <= 0) continue;
      final eased = Curves.easeInOutCubic.transform(travel);
      final startAngle = (math.pi * 2 * i / _threads.length) - .35;
      final start = Offset(
        center.dx + math.cos(startAngle) * reach,
        center.dy + math.sin(startAngle) * reach,
      );
      final endRadius = 78.0;
      final end = Offset(
        center.dx + math.cos(startAngle + 2.4) * endRadius,
        center.dy + math.sin(startAngle + 2.4) * endRadius,
      );
      final control = Offset(
        center.dx + math.cos(startAngle + 1.1) * (reach * (1 - eased * .55)),
        center.dy + math.sin(startAngle + 1.1) * (reach * (1 - eased * .55)),
      );
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final drawn = metrics.first.extractPath(0, metrics.first.length * eased);
      final fade = travel < .12 ? travel / .12 : (travel > .88 ? (1 - ((travel - .88) / .12)) : 1.0);
      paint
        ..strokeWidth = 3.2
        ..color = color.withOpacity(.18 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(drawn, paint);
      paint
        ..maskFilter = null
        ..strokeWidth = 2.4
        ..color = color.withOpacity(.78 * fade);
      canvas.drawPath(drawn, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SocialThreadInflowPainter oldDelegate) => oldDelegate.progress != progress;
}

class _CliporaMarkPainter extends CustomPainter {
  final double progress;
  const _CliporaMarkPainter({required this.progress});

  static const _ribbons = <Color>[
    Color(0xFF00F2EA),
    Color(0xFFFF0050),
    Color(0xFF1877F2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final tile = RRect.fromRectAndRadius(
      Rect.fromCircle(center: center, radius: size.shortestSide * .46),
      Radius.circular(size.shortestSide * .22),
    );
    final tileOpacity = ((progress - .08) / .28).clamp(0.0, 1.0).toDouble();
    canvas.drawRRect(
      tile,
      Paint()..color = const Color(0xFF07111F).withOpacity(.92 * tileOpacity),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withOpacity(.10 * tileOpacity),
    );

    final arc = Rect.fromCircle(center: center, radius: size.shortestSide * .27);
    final cProgress = ((progress - .18) / .52).clamp(0.0, 1.0).toDouble();
    final triProgress = ((progress - .58) / .28).clamp(0.0, 1.0).toDouble();

    for (var i = 0; i < _ribbons.length; i++) {
      final ribbon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * (.11 - i * .018)
        ..color = _ribbons[i].withOpacity(.90 - i * .12);
      canvas.drawArc(arc.inflate(i * size.shortestSide * .012), math.pi * .58, math.pi * 1.68 * cProgress, false, ribbon);
    }

    final tri = Path()
      ..moveTo(center.dx - size.width * .02, center.dy - size.height * .10)
      ..lineTo(center.dx - size.width * .02, center.dy + size.height * .10)
      ..lineTo(center.dx + size.width * .13, center.dy)
      ..close();
    if (triProgress > 0) {
      canvas.drawPath(
        tri,
        Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white.withOpacity(.92 * triProgress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CliporaMarkPainter oldDelegate) => oldDelegate.progress != progress;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final pages = const [DownloadsScreen(), HistoryScreen(), SessionScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF20B0D12),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(.08))),
              ),
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) => setState(() => index = value),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.south_west_rounded), selectedIcon: Icon(Icons.download_rounded), label: 'Save'),
                    NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Library'),
                    NavigationDestination(icon: Icon(Icons.lock_outline_rounded), selectedIcon: Icon(Icons.lock_rounded), label: 'Access'),
                    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
