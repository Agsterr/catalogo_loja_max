package com.max.loja.delivery;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import lombok.Getter;
import lombok.Setter;

/** Pagamento da assinatura do entregador: PENDING até a confirmação (admin hoje; provedor de pagamento depois). */
@Getter
@Setter
@Entity
public class CourierPayment {

    public static final String PENDING = "PENDING";
    public static final String CONFIRMED = "CONFIRMED";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long courierId;

    @Column(nullable = false)
    private BigDecimal amount;

    @Column(nullable = false, unique = true)
    private String reference;

    @Column(nullable = false)
    private String status = PENDING;

    /** PIX_MANUAL (chave da plataforma + confirmação do admin), ADMIN (cortesia) ou o provedor automático no futuro. */
    @Column(nullable = false)
    private String method = "PIX_MANUAL";

    private int periodDays = 30;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    private LocalDateTime confirmedAt;
    private Long confirmedBy;
}
