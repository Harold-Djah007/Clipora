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
        scaffoldBackgroundColor: const Color(0xFF020716),
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
          indicatorColor: _cyan.withOpacity(.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                letterSpacing: -.15,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w900 : FontWeight.w600,
                color: states.contains(WidgetState.selected) ? const Color(0xFFE0F7FF) : Colors.white70,
              )),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: states.contains(WidgetState.selected) ? 24 : 22,
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
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            borderSide: BorderSide(color: Color(0xFF22D3EE), width: 1.5),
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
    Timer(const Duration(milliseconds: 3050), () {
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2950))..forward();
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
                painter: _SocialLaunchStreakPainter(progress: Curves.easeInOutCubic.transform(_controller.value)),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final p = _controller.value;
                final textOpacity = ((p - .58) / .30).clamp(0.0, 1.0).toDouble();
                final scale = .88 + (.12 * Curves.easeOutBack.transform(p.clamp(0.0, 1.0).toDouble()));
                return Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 196,
                        height: 196,
                        child: CustomPaint(
                          painter: _SocialCliporaLogoPainter(progress: Curves.easeInOutCubic.transform(p), showWordmark: false),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Opacity(
                        opacity: textOpacity,
                        child: const Column(
                          children: [
                            Text(
                              'Clipora',
                              style: TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.5),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'all socials • one tap • gallery',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 12.5,
                                letterSpacing: 2.6,
                                fontWeight: FontWeight.w800,
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

class _SocialLaunchStreakPainter extends CustomPainter {
  final double progress;
  const _SocialLaunchStreakPainter({required this.progress});

  static const colors = <Color>[
    Color(0xFF00F2EA),
    Color(0xFFFF0050),
    Color(0xFFFFFFFF),
    Color(0xFF050505),
    Color(0xFFFEDA75),
    Color(0xFFFA7E1E),
    Color(0xFFD62976),
    Color(0xFF962FBF),
    Color(0xFF1877F2),
    Color(0xFF1DA1F2),
    Color(0xFFE60023),
    Color(0xFFFFFC00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = math.max(size.width, size.height) * .72;
    final streakPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 42; i++) {
      final phase = i / 42.0;
      final lane = colors[i % colors.length];
      final travel = ((progress * 1.22) - (phase * .35)).clamp(0.0, 1.0).toDouble();
      final eased = Curves.easeOutCubic.transform(travel);
      final angle = (math.pi * 2 * phase) + (math.sin(i * 1.7) * .42) + (progress * math.pi * .7);
      final startR = maxRadius * (.84 + (.22 * math.sin(i * 2.3)));
      final endR = 100 + (18 * math.sin(i * .9));
      final radius = startR + ((endR - startR) * eased);
      final head = Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);
      final tailR = radius + 58 + (18 * math.sin(i));
      final tail = Offset(center.dx + math.cos(angle - .08) * tailR, center.dy + math.sin(angle - .08) * tailR);
      final fadeIn = travel < .08 ? travel / .08 : 1.0;
      final fadeOut = travel > .94 ? (1 - ((travel - .94) / .06)) : 1.0;
      final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0).toDouble();

      streakPaint
        ..strokeWidth = 2.0 + ((i % 5) * .75)
        ..shader = LinearGradient(
          colors: [lane.withOpacity(0), lane.withOpacity(.78 * opacity), Colors.white.withOpacity(.34 * opacity)],
        ).createShader(Rect.fromPoints(tail, head));
      canvas.drawLine(tail, head, streakPaint);

      final particlePaint = Paint()..color = lane.withOpacity(.65 * opacity);
      canvas.drawCircle(head, 1.6 + (2.2 * (1 - travel)), particlePaint);
    }

    final ringProgress = ((progress - .62) / .26).clamp(0.0, 1.0).toDouble();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..shader = SweepGradient(colors: colors).createShader(Rect.fromCircle(center: center, radius: 126));
    canvas.drawArc(Rect.fromCircle(center: center, radius: 122), -math.pi / 2, math.pi * 2 * ringProgress, false, ring);
  }

  @override
  bool shouldRepaint(covariant _SocialLaunchStreakPainter oldDelegate) => oldDelegate.progress != progress;
}

class _SocialCliporaLogoPainter extends CustomPainter {
  final double progress;
  final bool showWordmark;
  const _SocialCliporaLogoPainter({required this.progress, required this.showWordmark});

  static const colors = _SocialLaunchStreakPainter.colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final p = progress;
    final iconRect = Rect.fromCenter(center: center, width: size.shortestSide * .86, height: size.shortestSide * .86);
    final rrect = RRect.fromRectAndRadius(iconRect, Radius.circular(size.shortestSide * .18));

    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF020617), Color(0xFF061A35), Color(0xFF16051F), Color(0xFF020617)],
      ).createShader(rect);
    canvas.drawRRect(rrect, bg);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * .024
      ..shader = SweepGradient(colors: colors).createShader(iconRect.inflate(8));
    canvas.drawRRect(rrect, border);

    final arcRect = Rect.fromCircle(center: center, radius: size.shortestSide * .26);
    final cProgress = ((p - .08) / .56).clamp(0.0, 1.0).toDouble();
    final triProgress = ((p - .48) / .34).clamp(0.0, 1.0).toDouble();
    final shine = .5 + (.5 * math.sin(p * math.pi * 2));

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .18
      ..color = const Color(0xFF00F2EA).withOpacity(.14 + (.08 * shine))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * .10);
    canvas.drawArc(arcRect.inflate(size.shortestSide * .02), math.pi * .58, math.pi * 1.72 * cProgress, false, glow);

    for (var i = 0; i < colors.length; i++) {
      final ribbon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * (.015 + ((i % 3) * .004))
        ..color = colors[i].withOpacity(i == 3 ? .28 : .60);
      canvas.drawArc(arcRect.inflate((i - 5.5) * size.shortestSide * .004), math.pi * (.59 + i * .011), math.pi * 1.68 * cProgress, false, ribbon);
    }

    final cPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .14
      ..shader = SweepGradient(startAngle: .2 + p, endAngle: math.pi * 2, colors: colors).createShader(arcRect.inflate(18));
    canvas.drawArc(arcRect, math.pi * .61, math.pi * 1.68 * cProgress, false, cPaint);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .018
      ..color = Colors.white.withOpacity(.44 * cProgress);
    canvas.drawArc(arcRect.deflate(size.shortestSide * .04), math.pi * 1.08, math.pi * .38 * cProgress, false, highlight);

    final triPath = Path()
      ..moveTo(center.dx - size.width * .020, center.dy - size.height * .100)
      ..lineTo(center.dx - size.width * .020, center.dy + size.height * .100)
      ..lineTo(center.dx + size.width * .135, center.dy)
      ..close();
    final metricPath = Path();
    for (final metric in triPath.computeMetrics()) {
      metricPath.addPath(metric.extractPath(0, metric.length * triProgress), Offset.zero);
    }

    final triGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .06
      ..color = const Color(0xFFFF0050).withOpacity(.38 * triProgress)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * .07);
    canvas.drawPath(metricPath, triGlow);

    if (triProgress >= .98) {
      final triFill = Paint()
        ..style = PaintingStyle.fill
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00F2EA), Color(0xFF1877F2), Color(0xFFD62976), Color(0xFFFFFC00)],
        ).createShader(triPath.getBounds());
      canvas.drawPath(triPath, triFill);
    }

    final triStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .025
      ..color = Colors.white.withOpacity(.48 * triProgress);
    canvas.drawPath(metricPath, triStroke);
  }

  @override
  bool shouldRepaint(covariant _SocialCliporaLogoPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.showWordmark != showWordmark;
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
      backgroundColor: const Color(0xFF020716),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xF20B1630), Color(0xEE111827), Color(0xF2071025)],
                  ),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const [BoxShadow(blurRadius: 26, offset: Offset(0, 10), color: Color(0x77000000))],
                ),
                clipBehavior: Clip.antiAlias,
                child: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) => setState(() => index = value),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.download_rounded), selectedIcon: Icon(Icons.flash_on_rounded), label: 'Save'),
                    NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: 'Library'),
                    NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.verified_user_rounded), label: 'Access'),
                    NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.bolt_rounded), label: 'Settings'),
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
