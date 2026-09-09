import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app_state.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/history/history_screen.dart';
import 'features/session/session_screen.dart';
import 'features/settings/settings_screen.dart';
import 'widgets/premium_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const CliporaApp()));
}

class CliporaApp extends StatelessWidget {
  const CliporaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00E5FF);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      primary: seed,
      secondary: const Color(0xFF8B5CF6),
      tertiary: const Color(0xFF22D3EE),
      surface: const Color(0xFF0A1024),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clipora',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF020716),
        fontFamily: 'Roboto',
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 76,
          backgroundColor: const Color(0xF2071025),
          elevation: 0,
          indicatorColor: const Color(0xFF00E5FF).withOpacity(.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11.5,
                letterSpacing: -.1,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w900 : FontWeight.w600,
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: states.contains(WidgetState.selected) ? 25 : 23,
                color: states.contains(WidgetState.selected) ? const Color(0xFF67E8F9) : Colors.white70,
              )),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xEE0B1630),
          hintStyle: const TextStyle(color: Colors.white38),
          labelStyle: const TextStyle(color: Colors.white70),
          helperStyle: const TextStyle(color: Color(0x73FFFFFF)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(color: Colors.white.withOpacity(.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFF22D3EE), width: 1.5),
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
    Timer(const Duration(milliseconds: 2850), () {
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2700))..forward();
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
      body: Stack(
        children: [
          const Positioned.fill(child: CliporaLiveBackground()),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _CliporaLaunchPainter(progress: Curves.easeInOutCubic.transform(_controller.value)),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final p = _controller.value;
                final textOpacity = ((p - .62) / .28).clamp(0.0, 1.0).toDouble();
                final scale = .94 + (.06 * Curves.easeOutBack.transform(p.clamp(0.0, 1.0).toDouble()));
                return Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 190,
                        child: CustomPaint(
                          painter: _CliporaMarkPainter(progress: Curves.easeInOutCubic.transform(p)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Opacity(
                        opacity: textOpacity,
                        child: Column(
                          children: const [
                            Text(
                              'Clipora',
                              style: TextStyle(
                                fontSize: 38,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.4,
                              ),
                            ),
                            SizedBox(height: 9),
                            Text(
                              'fast • private • yours',
                              style: TextStyle(
                                color: Color(0xB3FFFFFF),
                                fontSize: 13,
                                letterSpacing: 3.4,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CliporaLaunchPainter extends CustomPainter {
  final double progress;
  const _CliporaLaunchPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final p = progress;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    for (var i = 0; i < 18; i++) {
      final phase = (i / 18.0);
      final travel = ((p * 1.15) - (phase * .42)).clamp(0.0, 1.0).toDouble();
      final angle = (phase * math.pi * 2.4) + (p * math.pi * 1.2);
      final startRadius = math.max(size.width, size.height) * (.46 + (.16 * math.sin(i)));
      final endRadius = 98.0 + (12 * math.sin(i * 2.1));
      final radius = startRadius + ((endRadius - startRadius) * Curves.easeOutCubic.transform(travel));
      final pos = Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);
      final tail = Offset(center.dx + math.cos(angle - .11) * (radius + 38), center.dy + math.sin(angle - .11) * (radius + 38));
      final opacity = ((travel < .04 ? travel / .04 : 1.0).clamp(0.0, 1.0).toDouble() * (1 - (travel > .96 ? (travel - .96) / .04 : 0)).clamp(0.0, 1.0).toDouble());
      glowPaint.shader = LinearGradient(
        colors: [
          Color(0x0000E5FF),
          Color.lerp(const Color(0xFF00E5FF), const Color(0xFFA855F7), phase)!.withOpacity(.55 * opacity),
        ],
      ).createShader(Rect.fromPoints(tail, pos));
      canvas.drawLine(tail, pos, glowPaint);
      final dot = Paint()..color = const Color(0xFF67E8F9).withOpacity(.62 * opacity);
      canvas.drawCircle(pos, 2.2 + (2.4 * (1 - travel)), dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CliporaLaunchPainter oldDelegate) => oldDelegate.progress != progress;
}

class _CliporaMarkPainter extends CustomPainter {
  final double progress;
  const _CliporaMarkPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .34;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final cProgress = ((progress - .10) / .58).clamp(0.0, 1.0).toDouble();
    final triProgress = ((progress - .52) / .32).clamp(0.0, 1.0).toDouble();
    final shine = (.5 + (.5 * math.sin(progress * math.pi * 2))).clamp(0.0, 1.0).toDouble();

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .27
      ..color = const Color(0xFF00E5FF).withOpacity(.18 + (.14 * shine))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawArc(rect.inflate(1), math.pi * .62, math.pi * 1.72 * cProgress, false, glow);

    final cPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .21
      ..shader = SweepGradient(
        startAngle: .4,
        endAngle: math.pi * 2,
        colors: const [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF22D3EE), Color(0xFFA855F7), Color(0xFF7C3AED)],
      ).createShader(rect.inflate(18));
    canvas.drawArc(rect, math.pi * .62, math.pi * 1.72 * cProgress, false, cPaint);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .045
      ..color = Colors.white.withOpacity(.36 * cProgress);
    canvas.drawArc(rect.deflate(8), math.pi * 1.15, math.pi * .42 * cProgress, false, highlight);

    final triPath = Path()
      ..moveTo(center.dx - size.width * .035, center.dy - size.height * .128)
      ..lineTo(center.dx - size.width * .035, center.dy + size.height * .128)
      ..lineTo(center.dx + size.width * .16, center.dy)
      ..close();
    final metricPath = Path();
    for (final metric in triPath.computeMetrics()) {
      metricPath.addPath(metric.extractPath(0, metric.length * triProgress), Offset.zero);
    }

    final triGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12
      ..color = const Color(0xFFA855F7).withOpacity(.55 * triProgress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawPath(metricPath, triGlow);

    final triFill = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF22D3EE), Color(0xFF2563EB), Color(0xFFA855F7)],
      ).createShader(triPath.getBounds());
    if (triProgress >= .98) canvas.drawPath(triPath, triFill);

    final triStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = Colors.white.withOpacity(.40 * triProgress);
    canvas.drawPath(metricPath, triStroke);
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
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(.12)),
              boxShadow: const [BoxShadow(blurRadius: 30, offset: Offset(0, 12), color: Color(0x99000000))],
            ),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), selectedIcon: Icon(Icons.rocket_launch_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.video_library_rounded), label: 'Library'),
                NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.verified_user_rounded), label: 'Access'),
                NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.bolt_rounded), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
