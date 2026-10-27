package com.max.loja.delivery;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/**
 * Corrida de entrega. NÃO usa {@code @TenantId}: o entregador vê corridas de várias lojas. Guarda uma cópia do que ele
 * precisa (loja, endereços, valor); o endereço do cliente só sai da API depois do aceite.
 */
@Getter
@Setter
@Entity
public class DeliveryJob {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private Long orderId;

    @Column(nullable = false)
    private String orderCode;

    @Column(nullable = false)
    private Long tenantId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private JobStatus status = JobStatus.OPEN;

    @Column(nullable = false)
    private String storeName;

    private String pickupAddress;

    @Column(nullable = false)
    private double pickupLat;

    @Column(nullable = false)
    private double pickupLng;

    private String city;

    @Column(nullable = false)
    private String dropoffAddress;

    @Column(nullable = false)
    private double dropoffLat;

    @Column(nullable = false)
    private double dropoffLng;

    @Column(nullable = false)
    private String customerName;

    private String customerPhone;

    private int itemCount;

    @Column(nullable = false)
    private BigDecimal distanceKm;

    /** O que o cliente paga ao entregador (0 quando a loja paga o frete) e o frete que o entregador recebe. */
    @Column(nullable = false)
    private BigDecimal customerFee;

    @Column(nullable = false)
    private BigDecimal courierFee;

    /** Quem paga o frete direto ao entregador: CUSTOMER (na entrega) ou STORE (na coleta). */
    @Column(nullable = false)
    private String freightPayer = "CUSTOMER";

    /** A loja mostra o de coleta; o cliente mostra o de entrega. O entregador digita os dois (nunca os vê). */
    @Column(nullable = false)
    private String pickupCode;

    @Column(nullable = false)
    private String deliveryCode;

    private Long courierId;

    /** Quantas vezes foi ao mural (reaberta quando o entregador desiste ou a loja chama de novo). */
    private int offers = 1;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(nullable = false)
    private LocalDateTime expiresAt;

    private LocalDateTime acceptedAt;
    private LocalDateTime pickedUpAt;
    private LocalDateTime deliveredAt;
    private LocalDateTime canceledAt;
    private String cancelReason;
}
