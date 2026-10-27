package com.max.loja.notification;

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

/** Aviso do sino. {@code userId} nulo = toda a equipe; preenchido = só aquele usuário. */
@Getter
@Setter
@Entity
public class Notification {

    public enum Type {
        // equipe
        NEW_ORDER, ORDER_CANCELED, LOW_STOCK, OUT_OF_STOCK,
        // cliente
        ORDER_STATUS, ORDER_PAID, BACK_IN_STOCK
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Type type;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String message;

    private Long orderId;

    private Long productId;

    private Long userId;

    /** Evita repetir o mesmo aviso. */
    private String dedupKey;

    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt = LocalDateTime.now();

    private LocalDateTime readAt;
}
