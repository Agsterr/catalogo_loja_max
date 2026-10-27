import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key, required this.reason, required this.onSignOut});

  final String reason;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.block_rounded, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('Sua conta foi bloqueada', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(reason, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline_rounded),
              label: const Text(AppConfig.supportEmail),
              onPressed: () => launchUrl(Uri.parse('mailto:${AppConfig.supportEmail}')),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onSignOut, child: const Text('Sair')),
          ]),
        ),
      ),
    );
  }
}

/// Conta certa no app errado (ex.: cliente no app do lojista): explica e oferece sair.
class WrongAppScreen extends StatelessWidget {
  const WrongAppScreen({super.key, required this.message, required this.onSignOut});

  final String message;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.swap_horiz_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Este app não é para esta conta', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: onSignOut, child: const Text('Sair e entrar com outra conta')),
          ]),
        ),
      ),
    );
  }
}
