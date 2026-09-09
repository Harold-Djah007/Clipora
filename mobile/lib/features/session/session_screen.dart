import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/threadvault_mark.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool showLogin = false;
  InAppWebViewController? controller;

  Future<void> _finish() async {
    final state = context.read<AppState>();
    await state.refreshSession();
    if (!mounted) return;
    if (state.sessionConnected) {
      setState(() => showLogin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Private Threads session connected.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active Threads login was detected yet. Finish signing in, then tap Done again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return showLogin ? _LoginBrowser(onDone: _finish, onClose: () => setState(() => showLogin = false), onCreated: (c) => controller = c) : _AccessHome(state: state, onConnect: () => setState(() => showLogin = true));
  }
}

class _LoginBrowser extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onDone;
  final ValueChanged<InAppWebViewController> onCreated;
  const _LoginBrowser({required this.onClose, required this.onDone, required this.onCreated});

  @override
  Widget build(BuildContext context) {
    return CliporaPage(
      padding: EdgeInsets.zero,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0D12),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.10))),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
              const ThreadVaultMark(size: 38),
              const SizedBox(width: 10),
              const Expanded(child: Text('Sign in to Threads', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              FilledButton.icon(onPressed: onDone, icon: const Icon(Icons.done_rounded), label: const Text('Done')),
            ]),
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('https://www.threads.com/login')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              thirdPartyCookiesEnabled: true,
              cacheEnabled: true,
            ),
            onWebViewCreated: onCreated,
          ),
        ),
      ]),
    );
  }
}

class _AccessHome extends StatelessWidget {
  final AppState state;
  final VoidCallback onConnect;
  const _AccessHome({required this.state, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return CliporaPage(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const CliporaSectionTitle(
            title: 'Access',
            subtitle: 'Sign in to Threads only when a private post needs it',
          ),
          const SizedBox(height: 18),
          CliporaHeroCard(
            child: Column(children: [
              const ThreadVaultMark(size: 96),
              const SizedBox(height: 12),
              Text(
                state.sessionConnected ? 'Session connected' : 'Optional Threads login',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.6),
              ),
              const SizedBox(height: 8),
              Text(
                state.sessionConnected
                    ? 'Clipora can resolve posts that your connected account is already allowed to view.'
                    : 'Clipora never asks for your password. Sign-in happens on Threads.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 18),
              CliporaPrimaryButton(
                onPressed: onConnect,
                icon: Icon(state.sessionConnected ? Icons.refresh_rounded : Icons.login_rounded, color: Colors.white),
                label: state.sessionConnected ? 'Reconnect' : 'Sign in to Threads',
              ),
              if (state.sessionConnected) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: state.disconnect,
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('Sign out'),
                  ),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          const PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Privacy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              _PrivacyRow(icon: Icons.password_rounded, text: 'Your password is typed into Threads, not Clipora.'),
              _PrivacyRow(icon: Icons.phone_android_rounded, text: 'Cookies stay in the device WebView session.'),
              _PrivacyRow(icon: Icons.timer_off_rounded, text: 'Auto-delete can expire your session after your chosen time.'),
              _PrivacyRow(icon: Icons.visibility_rounded, text: 'Private media works only when you are already allowed to view it.'),
            ]),
          ),
          const SizedBox(height: 16),
          const PremiumCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('For private videos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              _PrivacyRow(icon: Icons.login_rounded, text: 'Log in once from Private Access.'),
              _PrivacyRow(icon: Icons.play_circle_fill_rounded, text: 'When capture opens, play the video once.'),
              _PrivacyRow(icon: Icons.video_file_rounded, text: 'Clipora saves the real MP4 instead of the poster image.'),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PrivacyRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF22D3EE).withOpacity(.12),
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF67E8F9)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.3))),
        ]),
      );
}
