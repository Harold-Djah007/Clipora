import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../services/settings_store.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/threadvault_mark.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController filename;

  @override
  void initState() {
    super.initState();
    filename = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      filename.text = context.read<AppState>().settings.filenameTemplate;
    });
  }

  @override
  void dispose() {
    filename.dispose();
    super.dispose();
  }

  Future<void> _update(AppSettings s) => context.read<AppState>().setSettings(s);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    if (filename.text.isEmpty) filename.text = s.filenameTemplate;

    return CliporaPage(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const CliporaSectionTitle(
            title: 'Settings',
            subtitle: 'Tune speed, privacy and saving behavior',
          ),
          const SizedBox(height: 18),
          CliporaHeroCard(
            child: Row(children: [
              const ThreadVaultMark(size: 70),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Text('Clipora Control', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                  SizedBox(height: 4),
                  Text('Built for background saving, clean MP4 capture and faster carousels.', style: TextStyle(color: Colors.white70, height: 1.25)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            glow: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PanelTitle(icon: Icons.bolt_rounded, title: 'Speed Engine', subtitle: 'Parallel downloads for batches and carousels'),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text('${s.maxConcurrentDownloads} parallel lane${s.maxConcurrentDownloads == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                CliporaPill(icon: Icons.speed_rounded, label: s.maxConcurrentDownloads >= 5 ? 'Turbo' : s.maxConcurrentDownloads >= 3 ? 'Balanced' : 'Safe'),
              ]),
              Slider(
                min: 1,
                max: 6,
                divisions: 5,
                label: '${s.maxConcurrentDownloads}',
                value: s.maxConcurrentDownloads.toDouble(),
                onChanged: (v) => _update(s.copyWith(maxConcurrentDownloads: v.round())),
              ),
              const Text(
                'Default is 5 lanes for faster carousels. Use 6 on strong Wi‑Fi; reduce to 3–4 for weak networks.',
                style: TextStyle(color: Colors.white54, height: 1.3),
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                icon: Icons.wifi_rounded,
                title: 'Wi‑Fi only',
                subtitle: 'Prevent media downloads on mobile data',
                value: s.wifiOnly,
                onChanged: (v) => _update(s.copyWith(wifiOnly: v)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PanelTitle(icon: Icons.drive_file_rename_outline_rounded, title: 'Filenames', subtitle: 'Clean naming for exported media'),
              const SizedBox(height: 14),
              TextField(
                controller: filename,
                decoration: const InputDecoration(
                  labelText: 'Filename template',
                  helperText: 'Available: {author}, {postId}, {index}',
                  prefixIcon: Icon(Icons.text_fields_rounded),
                ),
                onSubmitted: (value) => _update(s.copyWith(filenameTemplate: value.trim().isEmpty ? '{author}_{postId}_{index}' : value.trim())),
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                icon: Icons.notes_rounded,
                title: 'Save caption',
                subtitle: 'Create a .txt file beside each saved item',
                value: s.includeCaption,
                onChanged: (v) => _update(s.copyWith(includeCaption: v)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PanelTitle(icon: Icons.shield_rounded, title: 'Privacy', subtitle: 'Your login stays in the device WebView'),
              const SizedBox(height: 8),
              _SwitchRow(
                icon: Icons.timer_off_rounded,
                title: 'Auto-delete session',
                subtitle: 'Expire connected Threads authentication automatically',
                value: s.autoDeleteSession,
                onChanged: (v) => _update(s.copyWith(autoDeleteSession: v)),
              ),
              if (s.autoDeleteSession) ...[
                const SizedBox(height: 10),
                Text('Session lifetime: ${s.sessionTtlHours} hours', style: const TextStyle(fontWeight: FontWeight.w800)),
                Slider(
                  min: 1,
                  max: 168,
                  divisions: 23,
                  label: '${s.sessionTtlHours} h',
                  value: s.sessionTtlHours.toDouble(),
                  onChanged: (v) => _update(s.copyWith(sessionTtlHours: v.round())),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          const PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PanelTitle(icon: Icons.workspace_premium_rounded, title: 'About Clipora', subtitle: 'Version 0.8.1 • video-safe share resolver'),
              SizedBox(height: 12),
              Text('Clipora is designed for media you own or are already authorized to view. It does not unlock private accounts or bypass Threads access controls.', style: TextStyle(color: Colors.white70, height: 1.35)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PanelTitle({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF8B5CF6)]),
        ),
        child: Icon(icon, color: Colors.white, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.25)),
      ])),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: const Color(0xFF67E8F9)),
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
    );
  }
}
