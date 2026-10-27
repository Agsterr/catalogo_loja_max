package com.max.loja.delivery;

import java.math.BigDecimal;

/**
 * Como o entregador paga a assinatura. Hoje {@link ManualPixProvider} (chave Pix da plataforma e confirmação pelo admin);
 * um provedor automático (Pix com QR e webhook) entra aqui sem mexer no resto: ao confirmar, chama
 * {@code CourierBilling.confirm}.
 */
public interface PaymentProvider {

    /** O que o app mostra para pagar. {@code pixKey}/{@code holder} vazios = pagamento ainda não configurado. */
    record Instructions(String method, String pixKey, String holder, String reference, BigDecimal amount, String message) {
    }

    Instructions charge(Long courierId, String reference, BigDecimal amount);
}
