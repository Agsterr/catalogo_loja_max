package com.max.loja.delivery;

import java.math.BigDecimal;
import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Entrega por entregador da plataforma.
 *
 * @param baseFee           valor fixo da corrida (R$)
 * @param perKm             valor por km (R$)
 * @param minFee            corrida nunca custa menos que isto
 * @param maxKm             além disto a plataforma não entrega
 * @param offerTtl          quanto tempo a corrida fica no mural antes de expirar
 * @param maxActiveJobs     corridas ao mesmo tempo para um entregador
 * @param commissionPercent parte da taxa que fica com a plataforma (0 = tudo vai para o entregador)
 * @param pushLimit         quantos entregadores (os mais próximos) recebem o push de uma corrida nova
 * @param freshPosition     até quando vale a última posição enviada pelo entregador
 */
@ConfigurationProperties("app.delivery")
public record DeliveryProperties(BigDecimal baseFee, BigDecimal perKm, BigDecimal minFee, Integer maxKm, Duration offerTtl,
                                 Integer maxActiveJobs, Integer commissionPercent, Integer pushLimit,
                                 Duration freshPosition) {

    public DeliveryProperties {
        baseFee = baseFee == null ? new BigDecimal("4.00") : baseFee;
        perKm = perKm == null ? new BigDecimal("1.50") : perKm;
        minFee = minFee == null ? new BigDecimal("6.00") : minFee;
        maxKm = maxKm == null ? 15 : maxKm;
        offerTtl = offerTtl == null ? Duration.ofMinutes(30) : offerTtl;
        maxActiveJobs = maxActiveJobs == null ? 2 : maxActiveJobs;
        commissionPercent = commissionPercent == null ? 0 : Math.max(0, Math.min(90, commissionPercent));
        pushLimit = pushLimit == null ? 100 : pushLimit;
        freshPosition = freshPosition == null ? Duration.ofMinutes(15) : freshPosition;
    }
}
