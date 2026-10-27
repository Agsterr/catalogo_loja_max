import 'package:loja_core/loja_core.dart';

/// Quem paga o frete: direto ao entregador, sem passar pela plataforma.
String freightWho(String payer) => payer == 'STORE' ? 'Frete pago pela loja na coleta' : 'Frete pago pelo cliente na entrega';

String freightShort(String payer) => payer == 'STORE' ? 'pago pela loja' : 'pago pelo cliente';

String receiveFromStore(double fee) => 'Receba ${money(fee)} da loja ao retirar o pedido.';

String receiveFromCustomer(double fee) => 'Receba ${money(fee)} do cliente na entrega (dinheiro ou Pix).';
