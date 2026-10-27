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

    private String description;
    private String whatsapp;
    private String instagram;
    private String pickupAddress;
    private boolean pickupEnabled = true;
    private boolean deliveryEnabled = true;

    @Column(nullable = false)
    private BigDecimal deliveryFee = BigDecimal.ZERO;

    /** Pedido a partir deste valor não paga entrega; nulo = sempre paga. */
    private BigDecimal freeDeliveryFrom;

    /** Logo (quadrado) e capa da vitrine, no R2 (ou disco). */
    private String logoUrl;
    private String logoKey;
    private String coverUrl;
    private String coverKey;

    /** Horário por dia da semana em JSON (veja {@code StoreHours}); nulo = não informado. */
    private String openingHours;

    /** Onde a loja fica: cidade/UF para filtrar e coordenadas (opcionais) para ordenar por distância. */
    private String city;
    private String state;
    private Double latitude;
    private Double longitude;

    /** Bloqueada pelo administrador da plataforma. */
    private boolean blocked;
    private String blockedReason;
    private LocalDateTime blockedAt;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();
}
