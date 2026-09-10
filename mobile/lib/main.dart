import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'features/downloads/clipora_2_downloads_screen.dart';
import 'features/history/history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'widgets/threadvault_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const CliporaApp()));
}

class CliporaApp extends StatelessWidget {
  const CliporaApp({super.key});

  static const _ink = Color(0xFF05070D);
  static const _card = Color(0xFF0B1220);
  static const _aqua = Color(0xFF00F2EA);
  static const _violet = Color(0xFF8B5CF6);
  static const _rose = Color(0xFFFF3D71);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _aqua,
      brightness: Brightness.dark,
      primary: _aqua,
      secondary: _violet,
      tertiary: _rose,
      surface: _card,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clipora 2.0',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        fontFamily: 'Roboto',
        textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: false),
        splashFactory: InkSparkle.splashFactory,
        navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: _aqua.withOpacity(.14),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              color: states.contains(WidgetState.selected) ? Colors.white : Colors.white54,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? _aqua : Colors.white54,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF101723),
          hintStyle: const TextStyle(color: Colors.white38),
          labelStyle: const TextStyle(color: Colors.white70),
          helperStyle: const TextStyle(color: Color(0x73FFFFFF)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: _aqua, width: 1.25),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 50),
            side: BorderSide(color: Colors.white.withOpacity(.18)),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _aqua,
          thumbColor: _aqua,
          inactiveTrackColor: Colors.white.withOpacity(.12),
          overlayColor: _aqua.withOpacity(.15),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? _aqua : Colors.white70,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? _violet.withOpacity(.58) : Colors.white24,
          ),
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
    Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
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
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final p = Curves.easeOutCubic.transform(_controller.value);
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _LaunchGridPainter(progress: p))),
              Center(
                child: Transform.scale(
                  scale: .92 + (.08 * p),
                  child: Opacity(
                    opacity: p,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ThreadVaultMark(size: 108, showGlow: true),
                        const SizedBox(height: 22),
                        const Text('Clipora 2.0', style: TextStyle(fontSize: 36, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.1)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white.withOpacity(.06),
                            border: Border.all(color: Colors.white.withOpacity(.10)),
                          ),
                          child: const Text('smart save engine', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2.6, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
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

class _LaunchGridPainter extends CustomPainter {
  const _LaunchGridPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [Color(0x3322D3EE), Color(0x0000F2EA), Color(0x22000000)],
        ).createShader(rect),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    for (var i = 0; i < 7; i++) {
      final radius = (size.shortestSide * (.18 + i * .075)) * progress;
      paint
        ..strokeWidth = 1.1
        ..color = Color.lerp(const Color(0xFF00F2EA), const Color(0xFFFF3D71), i / 6)!.withOpacity(.18 * (1 - i * .08));
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi * 1.1, math.pi * 1.4, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaunchGridPainter oldDelegate) => oldDelegate.progress != progress;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final pages = const [Clipora2DownloadsScreen(), HistoryScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE60A0F1C),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(.10)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.32), blurRadius: 25, offset: const Offset(0, 12))],
              ),
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (value) => setState(() => index = value),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.auto_awesome_rounded), selectedIcon: Icon(Icons.bolt_rounded), label: 'Save'),
                    NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library_rounded), label: 'Library'),
                    NavigationDestination(icon: Icon(Icons.tune_rounded), selectedIcon: Icon(Icons.settings_suggest_rounded), label: 'Settings'),
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
