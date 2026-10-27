package com.max.loja.store;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Loja da plataforma (o tenant). Clientes chegam a ela pelo endereço {@code slug}. */
@Getter
@Setter
@Entity
public class Store {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String slug;

    @Column(nullable = false)
    private String name;

    private String whatsapp;
    private String instagram;
    private String pickupAddress;
    private boolean pickupEnabled = true;
    private boolean deliveryEnabled = true;

    @Column(nullable = false)
    private BigDecimal deliveryFee = BigDecimal.ZERO;

    /** Pedido a partir deste valor não paga entrega; nulo = sempre paga. */
    private BigDecimal freeDeliveryFrom;

    /** Bloqueada pelo administrador da plataforma. */
    private boolean blocked;
    private String blockedReason;
    private LocalDateTime blockedAt;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
