package com.max.loja.store;

import java.math.BigDecimal;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Dados da loja (linha única, id 1). */
@Getter
@Setter
@Entity
public class StoreSettings {

    @Id
    private Long id = 1L;

    private String name;
    private String whatsapp;
    private String instagram;
    private String pickupAddress;
    private boolean pickupEnabled = true;
    private boolean deliveryEnabled = true;
    private BigDecimal deliveryFee = BigDecimal.ZERO;
    /** Pedido a partir deste valor não paga entrega; nulo = sempre paga. */
    private BigDecimal freeDeliveryFrom;
}
