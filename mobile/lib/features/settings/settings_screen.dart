import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../services/resolver_url.dart';
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
  late final TextEditingController resolver;
  String? resolverStatus;
  bool resolverBusy = false;

  @override
  void initState() {
    super.initState();
    filename = TextEditingController();
    resolver = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<AppState>().settings;
      filename.text = s.filenameTemplate;
      resolver.text = s.resolverUrl;
    });
  }

  @override
  void dispose() {
    filename.dispose();
    resolver.dispose();
    super.dispose();
  }

  Future<void> _update(AppSettings s) => context.read<AppState>().setSettings(s);

  Future<bool> _saveResolver() async {
    final raw = resolver.text.trim().isEmpty ? ResolverUrl.defaultValue : resolver.text.trim();
    if (!ResolverUrl.isAllowed(raw)) {
      setState(() => resolverStatus = 'Use http://127.0.0.1:8010, http://10.0.2.2:8010, or your PC LAN IP such as http://192.168.1.10:8010.');
      return false;
    }
    final value = ResolverUrl.normalize(raw);
    resolver.text = value;
    await _update(context.read<AppState>().settings.copyWith(resolverUrl: value));
    setState(() => resolverStatus = 'Saved $value');
    return true;
  }

  Future<void> _testResolver() async {
    final saved = await _saveResolver();
    if (!saved || !mounted) return;
    setState(() {
      resolverBusy = true;
      resolverStatus = 'Checking backend…';
    });
    try {
      final base = await context.read<AppState>().universalResolver.ping();
      if (!mounted) return;
      setState(() => resolverStatus = 'Connected: $base');
    } catch (error) {
      if (!mounted) return;
      setState(() => resolverStatus = error.toString().replaceFirst('Bad state: ', '').replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => resolverBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    if (filename.text.isEmpty) filename.text = s.filenameTemplate;
    if (resolver.text.isEmpty) resolver.text = s.resolverUrl;

    return CliporaPage(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const CliporaSectionTitle(
            title: 'Settings',
            subtitle: 'Resolver, downloads, filenames, and session privacy',
          ),
          const SizedBox(height: 18),
          CliporaHeroCard(
            child: Row(children: [
              const ThreadVaultMark(size: 70),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Text('Clipora', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.4)),
                  SizedBox(height: 4),
                  Text('A quiet saver for links you can already view.', style: TextStyle(color: Colors.white70, height: 1.3)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            glow: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PanelTitle(
                icon: Icons.dns_rounded,
                title: 'Resolver',
                subtitle: 'PC backend the phone uses for TikTok, X, YouTube, and the rest',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: resolver,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Resolver URL',
                  helperText: 'Same Wi-Fi: http://192.168.x.x:8010   USB: http://127.0.0.1:8010',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                onSubmitted: (_) => _saveResolver(),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: resolverBusy ? null : _saveResolver,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save URL'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: resolverBusy ? null : _testResolver,
                    icon: resolverBusy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.health_and_safety_outlined, size: 18),
                    label: Text(resolverBusy ? 'Checking…' : 'Test'),
                  ),
                ),
              ]),
              if (resolverStatus != null) ...[
                const SizedBox(height: 10),
                Text(resolverStatus!, style: const TextStyle(color: Colors.white70, height: 1.35)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            glow: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PanelTitle(icon: Icons.speed_rounded, title: 'Downloads', subtitle: 'How many files to fetch at once'),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text('${s.maxConcurrentDownloads} at a time', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                CliporaPill(icon: Icons.speed_rounded, label: s.maxConcurrentDownloads >= 5 ? 'Faster' : s.maxConcurrentDownloads >= 3 ? 'Balanced' : 'Gentle'),
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
                'Higher values finish carousels sooner. Lower them on a weak connection.',
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
              _PanelTitle(icon: Icons.info_outline_rounded, title: 'About', subtitle: 'Clipora 0.8.5'),
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withOpacity(.05),
        ),
        child: Icon(icon, color: const Color(0xFF8BE9E0), size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
      secondary: Icon(icon, color: const Color(0xFF8BE9E0)),
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
    );
  }
}
