import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/app_state.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/history/history_screen.dart';
import 'features/session/session_screen.dart';
import 'features/settings/settings_screen.dart';
import 'widgets/clipora_launch.dart';

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
    Timer(const Duration(milliseconds: 3200), () {
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
