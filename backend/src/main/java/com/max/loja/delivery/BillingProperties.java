package com.max.loja.delivery;

import java.math.BigDecimal;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Assinatura do entregador (o único dinheiro que passa pela plataforma): depois das entregas grátis, uma mensalidade.
 *
 * @param courierMonthly valor da mensalidade (R$)
 * @param freeDeliveries entregas grátis por aparelho e por CPF
 * @param periodDays     dias que cada pagamento confirmado libera
 * @param pixKey         chave Pix da plataforma mostrada ao entregador (enquanto não há cobrança automática)
 * @param pixHolder      nome do recebedor mostrado junto com a chave
 */
@ConfigurationProperties("app.billing")
public record BillingProperties(BigDecimal courierMonthly, Integer freeDeliveries, Integer periodDays, String pixKey,
                                String pixHolder) {

    public BillingProperties {
        courierMonthly = courierMonthly == null ? new BigDecimal("24.99") : courierMonthly;
        freeDeliveries = freeDeliveries == null ? 5 : freeDeliveries;
        periodDays = periodDays == null ? 30 : periodDays;
        pixKey = pixKey == null ? "" : pixKey;
        pixHolder = pixHolder == null ? "" : pixHolder;
    }
}
