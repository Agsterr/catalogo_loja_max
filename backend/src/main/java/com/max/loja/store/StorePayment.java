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

/** Pagamento da mensalidade da loja. Não é por loja ({@code @TenantId}): o admin da plataforma lista as de todas. */
@Getter
@Setter
@Entity
public class StorePayment {

    public static final String PENDING = "PENDING";
    public static final String CONFIRMED = "CONFIRMED";

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long storeId;

    @Column(nullable = false)
    private BigDecimal amount;

    @Column(nullable = false, unique = true)
    private String reference;

    @Column(nullable = false)
    private String status = PENDING;

    @Column(nullable = false)
    private String method = "PIX_MANUAL";

    private int periodDays = 30;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    private LocalDateTime confirmedAt;
    private Long confirmedBy;
}
