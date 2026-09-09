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
          height: 74,
          backgroundColor: const Color(0xEE071025),
          elevation: 22,
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
          helperStyle: const TextStyle(color: Colors.white45),
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
      home: const HomeShell(),
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
      extendBody: true,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(.10)),
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
