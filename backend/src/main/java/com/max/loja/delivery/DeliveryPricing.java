package com.max.loja.delivery;

import java.math.BigDecimal;
import java.math.RoundingMode;

import org.springframework.stereotype.Component;

/** Quanto custa a corrida para o cliente e quanto fica para o entregador. Ponto único para trocar a regra (por cidade etc.). */
@Component
public class DeliveryPricing {

    private final DeliveryProperties props;

    public DeliveryPricing(DeliveryProperties props) {
        this.props = props;
    }

    public int maxKm() {
        return props.maxKm();
    }

    public boolean covers(double km) {
        return km <= props.maxKm();
    }

    /** Taxa cobrada do cliente para {@code km} quilômetros. */
    public BigDecimal customerFee(double km) {
        BigDecimal fee = props.baseFee().add(props.perKm().multiply(BigDecimal.valueOf(km))).setScale(2, RoundingMode.HALF_UP);
        return fee.max(props.minFee());
    }

    /** O que vai para o entregador (a taxa menos a comissão da plataforma). */
    public BigDecimal courierPay(BigDecimal customerFee) {
        return customerFee.multiply(BigDecimal.valueOf(100 - props.commissionPercent()))
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
    }
}
