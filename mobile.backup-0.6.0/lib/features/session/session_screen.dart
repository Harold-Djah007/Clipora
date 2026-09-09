import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../widgets/premium_card.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool showLogin = false;
  InAppWebViewController? controller;

  Future<void> _finish() async {
    await context.read<AppState>().refreshSession();
    if (mounted) setState(() => showLogin = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Private access', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text('Your Threads login stays on this device', style: TextStyle(color: Colors.white60)),
            ])),
            Icon(state.sessionConnected ? Icons.verified_user_rounded : Icons.lock_outline_rounded),
          ]),
        ),
        Expanded(
          child: showLogin
              ? Column(children: [
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(children: [
                        IconButton(onPressed: () => setState(() => showLogin = false), icon: const Icon(Icons.close_rounded)),
                        const Expanded(child: Text('Sign in to Threads, then tap Done')),
                        FilledButton(onPressed: _finish, child: const Text('Done')),
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
                      onWebViewCreated: (c) => controller = c,
                    ),
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
                  children: [
                    PremiumCard(
                      child: Column(children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: state.sessionConnected ? Colors.green.withOpacity(.15) : Colors.white10,
                          child: Icon(state.sessionConnected ? Icons.lock_open_rounded : Icons.lock_rounded, size: 32),
                        ),
                        const SizedBox(height: 14),
                        Text(state.sessionConnected ? 'Threads session connected' : 'Connect your Threads session',
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          state.sessionConnected
                              ? 'Private posts that this account can already view can be resolved automatically.'
                              : 'Sign in inside ThreadVault once. Your password is entered directly into Threads, not into ThreadVault.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => setState(() => showLogin = true),
                            icon: Icon(state.sessionConnected ? Icons.refresh_rounded : Icons.login_rounded),
                            label: Text(state.sessionConnected ? 'Reconnect session' : 'Connect Threads'),
                          ),
                        ),
                        if (state.sessionConnected) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: state.disconnect,
                              icon: const Icon(Icons.delete_forever_rounded),
                              label: const Text('Delete session now'),
                            ),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const PremiumCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Privacy design', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        SizedBox(height: 12),
                        _PrivacyRow(icon: Icons.password_rounded, text: 'ThreadVault never asks for or stores your Threads password.'),
                        _PrivacyRow(icon: Icons.phone_android_rounded, text: 'Authentication cookies remain in the device WebView cookie jar.'),
                        _PrivacyRow(icon: Icons.timer_off_rounded, text: 'Automatic expiry can wipe the connected session after your chosen TTL.'),
                        _PrivacyRow(icon: Icons.visibility_rounded, text: 'Private posts work only when the connected account is already allowed to view them.'),
                      ]),
                    ),
                  ],
                ),
        ),
      ]),
    );
  }
}

class _PrivacyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PrivacyRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ]),
      );
}
