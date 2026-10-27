import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

import 'register_screen.dart';

/// Tela inicial sem login: entrar ou pedir o cadastro de entregador.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            Icon(Icons.two_wheeler_rounded, size: 80, color: scheme.primary),
            const SizedBox(height: 12),
            Text('Loja Max Entregador', textAlign: TextAlign.center, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Receba corridas das lojas da sua região, entregue e acompanhe seus ganhos.',
                textAlign: TextAlign.center, style: t.bodyLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterCourierScreen(session: session))),
              icon: const Icon(Icons.how_to_reg_rounded),
              label: const Text('Quero ser entregador'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(
                    session: session,
                    allowRegister: false,
                    title: 'Loja Max Entregador',
                    subtitle: 'Entre para ver as corridas da sua região',
                    icon: Icons.two_wheeler_rounded,
                  ))),
              child: const Text('Já tenho cadastro · Entrar'),
            ),
            const SizedBox(height: 8),
            Text('Seu cadastro passa por uma análise antes de liberar as corridas.', textAlign: TextAlign.center, style: t.bodySmall),
          ]),
        ),
      ),
    );
  }
}
