import 'package:flutter/material.dart';
import 'package:loja_core/loja_core.dart';

/// Quem paga o frete: direto ao entregador, sem passar pela plataforma.
String freightWho(String payer) => payer == 'STORE' ? 'Frete pago pela loja na coleta' : 'Frete pago pelo cliente na entrega';

String freightShort(String payer) => payer == 'STORE' ? 'pago pela loja' : 'pago pelo cliente';

String receiveFromStore(double fee) => 'Receba ${money(fee)} da loja ao retirar o pedido.';

String receiveFromCustomer(double fee) => 'Receba ${money(fee)} do cliente na entrega (dinheiro ou Pix).';

/// Valor da corrida em destaque: frete + bônus da loja.
double jobTotal(double fee, double bonus) => fee + bonus;

String bonusLabel(double bonus) => 'Bônus +${money(bonus)} pago pela loja na coleta';

/// Lembretes do passo da coleta: o que receber da loja (frete se a loja paga, e o bônus sempre).
List<String> pickupReminders({required double fee, required double bonus, required bool storePays}) => [
      if (storePays) receiveFromStore(fee),
      if (bonus > 0) 'Receba o bônus de ${money(bonus)} da loja ao retirar o pedido.',
    ];

/// "★ 4,8 (23 avaliações)" ou "Sem avaliações ainda".
String ratingText(double? avg, int count) {
  if (avg == null || count == 0) return 'Sem avaliações ainda';
  return '★ ${avg.toStringAsFixed(1).replaceAll('.', ',')} ($count ${count == 1 ? 'avaliação' : 'avaliações'})';
}

/// Selo do bônus da loja.
class BonusBadge extends StatelessWidget {
  const BonusBadge(this.bonus, {super.key});

  final double bonus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bolt_rounded, size: 16, color: scheme.onTertiaryContainer),
        const SizedBox(width: 4),
        Flexible(child: Text(bonusLabel(bonus), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer))),
      ]),
    );
  }
}
