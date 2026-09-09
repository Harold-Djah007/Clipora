import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../services/settings_store.dart';
import '../../widgets/premium_card.dart';

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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
        children: [
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text('Control filenames, captions and privacy', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 22),
          PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Downloads', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: filename,
                decoration: const InputDecoration(
                  labelText: 'Filename template',
                  helperText: 'Available: {author}, {postId}, {index}',
                ),
                onSubmitted: (value) => _update(s.copyWith(filenameTemplate: value.trim().isEmpty ? '{author}_{postId}_{index}' : value.trim())),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: s.includeCaption,
                onChanged: (v) => _update(s.copyWith(includeCaption: v)),
                title: const Text('Save caption'),
                subtitle: const Text('Create a .txt file next to each downloaded item'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: s.wifiOnly,
                onChanged: (v) => _update(s.copyWith(wifiOnly: v)),
                title: const Text('Wi-Fi only'),
                subtitle: const Text('Block media downloads while using mobile data'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Private session', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: s.autoDeleteSession,
                onChanged: (v) => _update(s.copyWith(autoDeleteSession: v)),
                title: const Text('Auto-delete session'),
                subtitle: const Text('Expire connected Threads authentication automatically'),
              ),
              if (s.autoDeleteSession) ...[
                const SizedBox(height: 6),
                Text('Session lifetime: ${s.sessionTtlHours} hours'),
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
              Text('ThreadVault Premium', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('Version 0.7.7 • hardened real-media workflow', style: TextStyle(color: Colors.white60)),
              SizedBox(height: 10),
              Text('ThreadVault is designed for media you own or are already authorized to view. It does not unlock private accounts or bypass Threads access controls.', style: TextStyle(color: Colors.white70)),
            ]),
          ),
        ],
      ),
    );
  }
}
